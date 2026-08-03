"""
╔══════════════════════════════════╗
║  🦊 KuramaBot — Mobile API       ║
╚══════════════════════════════════╝

FastAPI backend that exposes video download capabilities
to the Kurama Flutter mobile app.

Run:  python api_server.py
Or:   uvicorn api_server:app --host 0.0.0.0 --port 8000
"""

import os
import sys
import hmac
import uuid
import time
import shutil
import logging
import threading

from fastapi import FastAPI, HTTPException, Header, Depends
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, field_validator

from config import (
    API_AUTH_KEY,
    API_HOST,
    API_PORT,
    TEMP_FOLDER,
    PLATFORM_RULES,
    ALLOWED_ORIGINS,
    MAX_URL_LENGTH,
    TASK_TTL,
)
from downloader import build_ydl_opts, fetch_info, download_single
from utils import get_platform, human_size, human_duration, clean_md

logger = logging.getLogger(__name__)

# ═══════════════════════════════════════════════════════
#  APP
# ═══════════════════════════════════════════════════════

app = FastAPI(
    title="KuramaBot API",
    version="1.1.0",
    description="Mobile backend for Kurama video downloader",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)

# ═══════════════════════════════════════════════════════
#  AUTH  (constant‑time comparison)
# ═══════════════════════════════════════════════════════

async def verify_auth(authorization: str | None = Header(None)):
    if API_AUTH_KEY is None:
        raise HTTPException(
            503,
            "API key not configured — set KURAMA_API_KEY in .env",
        )
    if not authorization:
        raise HTTPException(401, "Missing Authorization header")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer":
        raise HTTPException(401, "Authorization scheme must be Bearer")
    # Constant-time comparison prevents timing-attack key extraction
    if not hmac.compare_digest(token.encode(), API_AUTH_KEY.encode()):
        raise HTTPException(401, "Invalid API key")
    return True

# ═══════════════════════════════════════════════════════
#  PYDANTIC MODELS  (with input validation)
# ═══════════════════════════════════════════════════════

class FetchRequest(BaseModel):
    url: str

    @field_validator("url")
    @classmethod
    def validate_url(cls, v: str) -> str:
        v = v.strip()
        if len(v) > MAX_URL_LENGTH:
            raise ValueError(f"URL must be under {MAX_URL_LENGTH} characters")
        if not v.startswith(("http://", "https://")):
            raise ValueError("URL must start with http:// or https://")
        return v

class DownloadRequest(BaseModel):
    url: str
    format: str = "video"  # video | audio | doc
    video_quality: str = "best"
    audio_quality: str = "best"

    @field_validator("url")
    @classmethod
    def validate_url(cls, v: str) -> str:
        v = v.strip()
        if len(v) > MAX_URL_LENGTH:
            raise ValueError(f"URL must be under {MAX_URL_LENGTH} characters")
        if not v.startswith(("http://", "https://")):
            raise ValueError("URL must start with http:// or https://")
        return v

    @field_validator("format")
    @classmethod
    def validate_format(cls, v: str) -> str:
        if v not in ("video", "audio", "doc"):
            raise ValueError("format must be video, audio, or doc")
        return v

class DownloadResponse(BaseModel):
    task_id: str
    status: str

# ═══════════════════════════════════════════════════════
#  DOWNLOAD TASK MANAGER  (with TTL cleanup)
# ═══════════════════════════════════════════════════════

# In-memory task store
# task_id -> { status, progress, filepath, file_size, error, platform, url }
download_tasks: dict[str, dict] = {}
_tasks_lock = threading.Lock()


def _purge_expired_tasks():
    """Remove completed/failed tasks older than TASK_TTL and delete their files."""
    now = time.time()
    expired = []
    with _tasks_lock:
        for tid, task in download_tasks.items():
            age = now - task.get("created_at", now)
            if age > TASK_TTL and task["status"] in ("completed", "failed"):
                expired.append(tid)
        for tid in expired:
            task = download_tasks.pop(tid)
            # Clean up the per-task temp folder
            filepath = task.get("filepath")
            if filepath:
                task_dir = os.path.dirname(filepath)
                if task_dir.startswith(os.path.join(TEMP_FOLDER, "mobile_api")):
                    shutil.rmtree(task_dir, ignore_errors=True)
    if expired:
        logger.info(f"[API] Purged {len(expired)} expired download tasks")


def background_download(task_id: str, url: str, platform: str, ydl_opts: dict):
    """Run the actual yt-dlp download in a daemon thread."""
    with _tasks_lock:
        task = download_tasks.get(task_id)
    if not task:
        return
    try:
        task["status"] = "downloading"
        filepath, info = download_single(url, ydl_opts)
        task["status"] = "completed"
        task["filepath"] = filepath
        task["progress"] = 100
        task["file_size"] = os.path.getsize(filepath) if os.path.exists(filepath) else 0
        task["title"] = info.get("title", "Unknown")
    except Exception as e:
        task["status"] = "failed"
        task["error"] = str(e)[:500]
        logger.error(f"[API] Download task {task_id} failed: {e}")


# ═══════════════════════════════════════════════════════
#  ENDPOINTS
# ═══════════════════════════════════════════════════════

@app.get("/api/health")
def health_check():
    return {"status": "ok", "app": "KuramaBot API", "version": "1.1.0"}


@app.get("/api/platforms")
def list_platforms(auth=Depends(verify_auth)):
    """Return all supported platforms with their emoji icons."""
    return {
        "platforms": [
            {"name": name, "emoji": emoji}
            for _, name, emoji in PLATFORM_RULES
        ]
    }


@app.post("/api/fetch-info")
def api_fetch_info(req: FetchRequest, auth=Depends(verify_auth)):
    """Fetch video/playlist metadata without downloading."""
    url = req.url  # already validated & stripped by Pydantic
    platform, icon = get_platform(url)

    try:
        info = fetch_info(url, platform)
    except Exception as e:
        raise HTTPException(400, str(e)[:300])

    entries = info.get("entries")
    # yt-dlp can return a generator — materialize it
    if entries is not None:
        entries = list(entries)
    is_playlist = entries is not None and len(entries) > 1

    return {
        "url": url,
        "platform": platform,
        "icon": icon,
        "title": clean_md(info.get("title") or info.get("webpage_title", "Unknown")),
        "uploader": clean_md(info.get("uploader") or info.get("channel", "Unknown")),
        "duration": info.get("duration"),
        "duration_str": human_duration(info.get("duration")),
        "filesize": info.get("filesize_approx") or info.get("filesize"),
        "filesize_str": human_size(
            info.get("filesize_approx") or info.get("filesize")
        ),
        "views": info.get("view_count"),
        "thumbnail": info.get("thumbnail"),
        "upload_date": info.get("upload_date"),
        "is_playlist": is_playlist,
        "playlist_count": len(entries) if is_playlist else 0,
    }


@app.post("/api/download", response_model=DownloadResponse)
def api_start_download(req: DownloadRequest, auth=Depends(verify_auth)):
    """Start a download in the background and return a task_id to poll."""
    # Purge stale tasks before creating new ones
    _purge_expired_tasks()

    url = req.url  # already validated & stripped by Pydantic
    platform, _ = get_platform(url)
    task_id = str(uuid.uuid4())

    # Per-task temp folder (sandboxed under TEMP_FOLDER/mobile_api/)
    save_folder = os.path.join(TEMP_FOLDER, "mobile_api", task_id)
    os.makedirs(save_folder, exist_ok=True)

    audio_only = req.format == "audio"
    send_as_doc = req.format == "doc"

    ydl_opts = build_ydl_opts(
        save_folder=save_folder,
        platform=platform,
        for_mobile=True,
        audio_only=audio_only,
        send_as_doc=send_as_doc,
        video_quality=req.video_quality,
        audio_quality=req.audio_quality,
    )

    with _tasks_lock:
        download_tasks[task_id] = {
            "status": "pending",
            "progress": 0,
            "filepath": None,
            "file_size": 0,
            "error": None,
            "platform": platform,
            "url": url,
            "title": None,
            "created_at": time.time(),
        }

    thread = threading.Thread(
        target=background_download,
        args=(task_id, url, platform, ydl_opts),
        daemon=True,
    )
    thread.start()

    return DownloadResponse(task_id=task_id, status="pending")


@app.get("/api/download/{task_id}")
def api_download_status(task_id: str, auth=Depends(verify_auth)):
    """Poll the status of a download task."""
    with _tasks_lock:
        task = download_tasks.get(task_id)
    if not task:
        raise HTTPException(404, "Download task not found")

    resp = {
        "task_id": task_id,
        "status": task["status"],
        "progress": task["progress"],
        "platform": task["platform"],
        "title": task.get("title"),
        "error": task.get("error"),
    }

    if task["status"] == "completed":
        resp["file_size"] = task.get("file_size", 0)
        resp["file_size_str"] = human_size(task.get("file_size", 0))

    return resp


@app.get("/api/download/{task_id}/file")
def api_download_file(task_id: str, auth=Depends(verify_auth)):
    """Download the completed file (path-traversal safe)."""
    with _tasks_lock:
        task = download_tasks.get(task_id)
    if not task:
        raise HTTPException(404, "Download task not found")
    if task["status"] != "completed":
        raise HTTPException(400, "Download not yet completed")
    if not task["filepath"] or not os.path.exists(task["filepath"]):
        raise HTTPException(404, "Download file not found on disk")

    # ── Path traversal guard ────────────────────────────
    # Ensure the file is within our expected temp directory
    real_path = os.path.realpath(task["filepath"])
    allowed_root = os.path.realpath(os.path.join(TEMP_FOLDER, "mobile_api"))
    if not real_path.startswith(allowed_root + os.sep) and real_path != allowed_root:
        logger.error(
            f"[API] Path traversal blocked: task {task_id} tried to serve {real_path}"
        )
        raise HTTPException(403, "File access denied")

    filename = os.path.basename(real_path)
    return FileResponse(
        path=real_path,
        filename=filename,
        media_type="application/octet-stream",
    )


# ═══════════════════════════════════════════════════════
#  RUNNER
# ═══════════════════════════════════════════════════════

def run_api_server():
    import uvicorn

    if API_AUTH_KEY is None:
        print("[ERR] Cannot start API server: KURAMA_API_KEY is not set in .env")
        print("      Set a strong random key, e.g.:")
        print("        KURAMA_API_KEY=$(python -c \"import secrets; print(secrets.token_urlsafe(32))\")")
        sys.exit(1)

    print(f"[API] KuramaBot API starting on {API_HOST}:{API_PORT}")
    uvicorn.run(app, host=API_HOST, port=API_PORT, log_level="info")


if __name__ == "__main__":
    run_api_server()
