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
import re
import json
import hmac
import uuid
import time
import shutil
import logging
import threading
import zipfile

from fastapi import FastAPI, HTTPException, Header, Depends, File, Form, UploadFile
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator

from config import (
    API_AUTH_KEY,
    API_ADMIN_KEY,
    API_HOST,
    API_PORT,
    TEMP_FOLDER,
    PLATFORM_RULES,
    ALLOWED_ORIGINS,
    MAX_URL_LENGTH,
    TASK_TTL,
    MONTHLY_SUB_PRICE_NPR,
    ESEWA_ID,
    KHALTI_ID,
    BANK_DETAILS,
)
from downloader import build_ydl_opts, fetch_info, download_single
from utils import get_platform, human_size, human_duration, clean_md
import user_config

logger = logging.getLogger(__name__)

API_VERSION = "1.1.1"
_APP_START_TIME = time.time()

# ═══════════════════════════════════════════════════════
#  APP
# ═══════════════════════════════════════════════════════

app = FastAPI(
    title="KuramaBot API",
    version=API_VERSION,
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

def _check_key(authorization: str | None, expected: str):
    """Validate a Bearer token with a constant-time comparison."""
    if not authorization:
        raise HTTPException(401, "Missing Authorization header")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer":
        raise HTTPException(401, "Authorization scheme must be Bearer")
    # Constant-time comparison prevents timing-attack key extraction
    if not hmac.compare_digest(token.encode(), expected.encode()):
        raise HTTPException(401, "Invalid API key")


async def verify_auth(authorization: str | None = Header(None)):
    if API_AUTH_KEY is None:
        raise HTTPException(
            503,
            "API key not configured — set KURAMA_API_KEY in .env",
        )
    _check_key(authorization, API_AUTH_KEY)
    return True


async def verify_admin(authorization: str | None = Header(None)):
    """Admin endpoints use KURAMA_ADMIN_KEY when set, else the main API key."""
    if API_AUTH_KEY is None:
        raise HTTPException(
            503,
            "API key not configured — set KURAMA_API_KEY in .env",
        )
    _check_key(authorization, API_ADMIN_KEY or API_AUTH_KEY)
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
    user_id: int
    format: str = "video"  # video | audio | doc
    video_quality: str = "best"
    audio_quality: str = "best"
    thumbnail: str | None = Field(
        default=None, max_length=MAX_URL_LENGTH
    )  # artwork URL echoed back for the app player
    playlist: bool = False  # download every video and bundle as a ZIP

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

    @field_validator("user_id")
    @classmethod
    def validate_user_id(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("user_id must be positive")
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

# Concurrency guard — keeps free-tier instances from spawning unbounded
# yt-dlp threads (the classic cause of render.com OOM / crash loops).
MAX_CONCURRENT_DOWNLOADS = int(os.getenv("MAX_CONCURRENT_DOWNLOADS", "5"))

# Playlist cap — protect free-tier instances from gigantic playlists.
PLAYLIST_MAX_ENTRIES = int(os.getenv("PLAYLIST_MAX_ENTRIES", "60"))

# Disk-backed task store: completed/failed downloads survive restarts and
# interrupted ones are marked failed so the app can offer a Retry.
_TASKS_FILE = os.path.join(TEMP_FOLDER, "mobile_api", "tasks.json")


def _save_tasks():
    """Persist the task store to disk (atomic replace)."""
    try:
        with _tasks_lock:
            snapshot = dict(download_tasks)
        os.makedirs(os.path.dirname(_TASKS_FILE), exist_ok=True)
        tmp_path = _TASKS_FILE + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as handle:
            json.dump(snapshot, handle)
        os.replace(tmp_path, _TASKS_FILE)
    except Exception:
        logger.exception("[API] Failed to persist task store")


def _load_tasks():
    """Recover the task store from disk. In-flight tasks are marked failed so
    the app can retry them (their spent credit is refunded by the failure)."""
    try:
        if not os.path.exists(_TASKS_FILE):
            return
        with open(_TASKS_FILE, encoding="utf-8") as handle:
            data = json.load(handle)
        if not isinstance(data, dict):
            return
        now = time.time()
        recovered: dict[str, dict] = {}
        for tid, task in data.items():
            if not isinstance(task, dict):
                continue
            if task.get("status") in ("pending", "downloading"):
                task = dict(task)
                task["status"] = "failed"
                task["error"] = "Server restarted while downloading — tap Retry."
                # Refund the credit spent by the interrupted attempt so a
                # Retry doesn't charge the user twice for one download.
                if task.get("credit_charged") and task.get("user_id"):
                    try:
                        user_config.refund_credit(int(task["user_id"]))
                    except Exception:
                        logger.exception("[API] Refund on recovery failed")
            age = now - (task.get("created_at") or now)
            if age > TASK_TTL and task.get("status") in ("completed", "failed"):
                continue  # already expired
            recovered[tid] = task
        if recovered:
            with _tasks_lock:
                download_tasks.update(recovered)
            logger.info(f"[API] Recovered {len(recovered)} tasks from disk")
    except Exception:
        logger.exception("[API] Failed to load task store")


_load_tasks()


def _active_download_count() -> int:
    with _tasks_lock:
        return sum(
            1
            for task in download_tasks.values()
            if task.get("status") in ("pending", "downloading")
        )


def _task_summary(task_id: str, task: dict) -> dict:
    """Public-safe snapshot of a task for the admin list."""
    created = task.get("created_at") or time.time()
    return {
        "task_id": task_id,
        "status": task.get("status"),
        "progress": task.get("progress"),
        "platform": task.get("platform"),
        "title": task.get("title"),
        "thumbnail": task.get("thumbnail"),
        "format": task.get("format"),
        "user_id": task.get("user_id"),
        "url": task.get("url"),
        "created_at": task.get("created_at"),
        "age_seconds": max(0, int(time.time() - created)),
        "file_size": task.get("file_size"),
        "speed_label": task.get("speed_label"),
        "eta_seconds": task.get("eta_seconds"),
        "error": task.get("error"),
    }


def _task_folder(task_id: str, task: dict) -> str | None:
    """The on-disk folder owned by a task, if any (path-guarded)."""
    root = os.path.join(TEMP_FOLDER, "mobile_api")
    filepath = task.get("filepath")
    if filepath:
        folder = os.path.dirname(filepath)
    else:
        folder = os.path.join(root, task_id)
    if folder and folder.startswith(root + os.sep):
        return folder
    return None


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
        _save_tasks()


def _download_progress_hook(task_id: str):
    def update(data: dict):
        if data.get("status") != "downloading":
            return
        total = data.get("total_bytes") or data.get("total_bytes_estimate") or 0
        downloaded = data.get("downloaded_bytes") or 0
        progress = int(downloaded * 100 / total) if total else 0
        speed = int(data.get("speed") or 0)
        eta = data.get("eta")
        with _tasks_lock:
            task = download_tasks.get(task_id)
            if task:
                task.update({
                    "progress": max(0, min(progress, 99)),
                    "speed_bytes_per_second": speed,
                    "speed_label": f"{human_size(speed)}/s" if speed else None,
                    "eta_seconds": int(eta) if eta is not None else None,
                })
    return update


def background_download(
    task_id: str,
    url: str,
    platform: str,
    ydl_opts: dict,
    user_id: int,
    credit_charged: bool,
    playlist: bool = False,
):
    """Run the actual yt-dlp download in a daemon thread."""
    if playlist:
        background_playlist_download(
            task_id, url, platform, ydl_opts, user_id, credit_charged
        )
        return
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
        if credit_charged:
            user_config.refund_credit(user_id)
        logger.error(f"[API] Download task {task_id} failed: {e}")
    finally:
        _save_tasks()


def background_playlist_download(
    task_id: str,
    url: str,
    platform: str,
    ydl_opts: dict,
    user_id: int,
    credit_charged: bool,
):
    """Download every video in a playlist, then bundle them into a ZIP."""
    from yt_dlp import YoutubeDL

    with _tasks_lock:
        task = download_tasks.get(task_id)
    if not task:
        return
    try:
        task["status"] = "downloading"
        task["title"] = "Playlist download"

        info_opts = {
            "skip_download": True,
            "quiet": True,
            "noplaylist": False,
            "extract_flat": "in_playlist",
        }
        with YoutubeDL(info_opts) as ydl:
            info = ydl.extract_info(url, download=False)
        entries = [e for e in (info.get("entries") or []) if e]
        if not entries:
            raise ValueError("No playlist entries found")
        entries = entries[:PLAYLIST_MAX_ENTRIES]
        total = len(entries)
        title = clean_md(
            info.get("title") or info.get("webpage_title") or "playlist"
        )
        save_folder = os.path.join(TEMP_FOLDER, "mobile_api", task_id)

        with _tasks_lock:
            if task_id in download_tasks:
                download_tasks[task_id]["title"] = title

        for i, entry in enumerate(entries, start=1):
            entry_url = (
                entry.get("webpage_url")
                or entry.get("url")
                or entry.get("original_url")
            )
            if not entry_url:
                continue
            download_single(entry_url, ydl_opts)
            with _tasks_lock:
                if task_id in download_tasks:
                    download_tasks[task_id]["progress"] = min(
                        99, int(i * 100 / total)
                    )

        zip_path = os.path.join(save_folder, f"{_safe_filename(title)}.zip")
        zip_name = os.path.basename(zip_path)
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for name in sorted(os.listdir(save_folder)):
                full = os.path.join(save_folder, name)
                if os.path.isfile(full) and name != zip_name:
                    zf.write(full, arcname=name)

        with _tasks_lock:
            if task_id in download_tasks:
                download_tasks[task_id].update({
                    "status": "completed",
                    "filepath": zip_path,
                    "progress": 100,
                    "file_size": os.path.getsize(zip_path),
                    "title": title,
                })
    except Exception as e:
        with _tasks_lock:
            if task_id in download_tasks:
                download_tasks[task_id].update({
                    "status": "failed",
                    "error": str(e)[:500],
                })
        if credit_charged:
            user_config.refund_credit(user_id)
        logger.error(f"[API] Playlist task {task_id} failed: {e}")
    finally:
        _save_tasks()


def _safe_filename(name: str) -> str:
    cleaned = re.sub(r"[^\w\-. ()[\]]", "_", name).strip(" .")
    return cleaned or "playlist"


# ═══════════════════════════════════════════════════════
#  ENDPOINTS
# ═══════════════════════════════════════════════════════

@app.get("/api/health")
def health_check():
    """Public liveness probe — also reports operator-relevant state."""
    return {
        "status": "ok",
        "app": "KuramaBot API",
        "version": API_VERSION,
        "api_key_configured": API_AUTH_KEY is not None,
        "active_downloads": _active_download_count(),
        "uptime_seconds": int(time.time() - _APP_START_TIME),
    }


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

    try:
        allowed, credit_charged = user_config.consume_download_credit(req.user_id)
    except Exception:
        logger.exception("[API] Credit check failed")
        raise HTTPException(500, "Server error while checking credits.")
    if not allowed:
        raise HTTPException(402, "No download credits remaining")

    # Per-task temp folder (sandboxed under TEMP_FOLDER/mobile_api/)
    save_folder = os.path.join(TEMP_FOLDER, "mobile_api", task_id)
    os.makedirs(save_folder, exist_ok=True)

    audio_only = req.format == "audio"
    send_as_doc = req.format == "doc"

    try:
        ydl_opts = build_ydl_opts(
            save_folder=save_folder,
            platform=platform,
            progress_hook=_download_progress_hook(task_id),
            for_mobile=True,
            audio_only=audio_only,
            send_as_doc=send_as_doc,
            video_quality=req.video_quality,
            audio_quality=req.audio_quality,
        )
    except Exception:
        logger.exception("[API] Failed to build download options")
        raise HTTPException(500, "Server error while preparing the download.")

    # Atomic capacity check + registration: prevents two simultaneous
    # requests from both passing the cap and spawning unbounded threads.
    with _tasks_lock:
        active = sum(
            1
            for task in download_tasks.values()
            if task.get("status") in ("pending", "downloading")
        )
        if active >= MAX_CONCURRENT_DOWNLOADS:
            if credit_charged:
                user_config.refund_credit(req.user_id)
            raise HTTPException(
                429,
                "Server is busy with other downloads right now. Try again in a minute.",
            )
        download_tasks[task_id] = {
            "status": "pending",
            "progress": 0,
            "filepath": None,
            "file_size": 0,
            "error": None,
            "platform": platform,
            "url": url,
            "thumbnail": req.thumbnail,
            "title": None,
            "created_at": time.time(),
            "format": req.format,
            "playlist": req.playlist,
            "video_quality": req.video_quality,
            "audio_quality": req.audio_quality,
            "user_id": req.user_id,
            "credit_charged": credit_charged,
            "speed_bytes_per_second": 0,
            "speed_label": None,
            "eta_seconds": None,
        }
    _save_tasks()

    thread = threading.Thread(
        target=background_download,
        args=(
            task_id,
            url,
            platform,
            ydl_opts,
            req.user_id,
            credit_charged,
            req.playlist,
        ),
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
        "format": task.get("format", "video"),
        "thumbnail": task.get("thumbnail"),
        "speed_bytes_per_second": task.get("speed_bytes_per_second"),
        "speed_label": task.get("speed_label"),
        "eta_seconds": task.get("eta_seconds"),
    }

    if task["status"] == "completed":
        resp["file_size"] = task.get("file_size", 0)
        resp["file_size_str"] = human_size(task.get("file_size", 0))
        # Actual on-disk filename so the app saves the correct extension
        # (e.g. .mp3 audio, .mp4 video) instead of guessing.
        resp["filename"] = os.path.basename(task.get("filepath") or "") or None

    return resp


@app.post("/api/download/{task_id}/retry")
def api_retry_download(task_id: str, auth=Depends(verify_auth)):
    """Re-run a failed download. Charges one credit (the failed attempt was
    refunded), resets the task, and spawns a fresh background thread."""
    with _tasks_lock:
        task = download_tasks.get(task_id)
        if not task:
            raise HTTPException(404, "Download task not found")
        if task["status"] != "failed":
            raise HTTPException(409, "Only failed downloads can be retried")

    url = task.get("url") or ""
    platform = task.get("platform") or get_platform(url)[0]
    user_id = task.get("user_id") or 0
    fmt = task.get("format", "video")
    is_playlist = bool(task.get("playlist"))

    try:
        allowed, credit_charged = user_config.consume_download_credit(user_id)
    except Exception:
        logger.exception("[API] Credit check failed on retry")
        raise HTTPException(500, "Server error while checking credits.")
    if not allowed:
        raise HTTPException(402, "No download credits remaining")

    save_folder = os.path.join(TEMP_FOLDER, "mobile_api", task_id)
    os.makedirs(save_folder, exist_ok=True)
    # Clear stale output from the failed attempt.
    for name in os.listdir(save_folder):
        try:
            os.remove(os.path.join(save_folder, name))
        except OSError:
            pass

    audio_only = fmt == "audio"
    send_as_doc = fmt == "doc"
    try:
        ydl_opts = build_ydl_opts(
            save_folder=save_folder,
            platform=platform,
            progress_hook=_download_progress_hook(task_id),
            for_mobile=True,
            audio_only=audio_only,
            send_as_doc=send_as_doc,
            video_quality=task.get("video_quality", "best"),
            audio_quality=task.get("audio_quality", "best"),
        )
    except Exception:
        logger.exception("[API] Failed to build retry options")
        if credit_charged:
            user_config.refund_credit(user_id)
        raise HTTPException(500, "Server error while preparing the download.")

    with _tasks_lock:
        active = sum(
            1
            for t in download_tasks.values()
            if t.get("status") in ("pending", "downloading")
        )
        if active >= MAX_CONCURRENT_DOWNLOADS:
            if credit_charged:
                user_config.refund_credit(user_id)
            raise HTTPException(
                429,
                "Server is busy with other downloads right now. Try again in a minute.",
            )
        task.update({
            "status": "pending",
            "progress": 0,
            "filepath": None,
            "file_size": 0,
            "error": None,
            "title": None,
            "speed_bytes_per_second": 0,
            "speed_label": None,
            "eta_seconds": None,
        })
    _save_tasks()

    thread = threading.Thread(
        target=background_download,
        args=(
            task_id,
            url,
            platform,
            ydl_opts,
            user_id,
            credit_charged,
            is_playlist,
        ),
        daemon=True,
    )
    thread.start()
    return {"status": "retried", "task_id": task_id}


def _sse_event(task_id: str) -> str:
    """Render one SSE frame for the task's current state."""
    with _tasks_lock:
        task = download_tasks.get(task_id)
    if not task:
        return 'event: error\ndata: {"detail":"Download task not found"}\n\n'
    data = {
        "task_id": task_id,
        "status": task["status"],
        "progress": task["progress"],
        "platform": task.get("platform"),
        "title": task.get("title"),
        "error": task.get("error"),
        "format": task.get("format", "video"),
        "thumbnail": task.get("thumbnail"),
        "speed_label": task.get("speed_label"),
        "eta_seconds": task.get("eta_seconds"),
    }
    if task["status"] == "completed":
        data["file_size"] = task.get("file_size", 0)
        data["file_size_str"] = human_size(task.get("file_size", 0))
        data["filename"] = os.path.basename(task.get("filepath") or "") or None
    return f"event: status\ndata: {json.dumps(data)}\n\n"


@app.get("/api/download/{task_id}/stream")
def api_download_stream(task_id: str, auth=Depends(verify_auth)):
    """Server-Sent Events stream of task status (app falls back to polling)."""
    def event_gen():
        last_state: tuple | None = None
        deadline = time.time() + 15 * 60  # hard cap: 15 minutes
        while time.time() < deadline:
            with _tasks_lock:
                task = download_tasks.get(task_id)
            if task is None:
                yield 'event: error\ndata: {"detail":"Download task not found"}\n\n'
                return
            state = (
                task["status"],
                task["progress"],
                task.get("speed_label"),
                task.get("title"),
                task.get("error"),
            )
            if state != last_state:
                yield _sse_event(task_id)
                last_state = state
                if task["status"] in ("completed", "failed"):
                    return
            time.sleep(1)
        yield 'event: done\ndata: {}\n\n'

    return StreamingResponse(
        event_gen(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


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
#  ADMIN ENDPOINTS  (task inspection & cleanup)
# ═══════════════════════════════════════════════════════

@app.get("/api/admin/tasks")
def api_admin_tasks(auth=Depends(verify_admin)):
    """List every download task with stats, newest first."""
    with _tasks_lock:
        tasks = [
            _task_summary(task_id, task)
            for task_id, task in download_tasks.items()
        ]
    counts: dict[str, int] = {}
    for task in tasks:
        status = task["status"] or "unknown"
        counts[status] = counts.get(status, 0) + 1
    return {
        "total": len(tasks),
        "counts": counts,
        "active": counts.get("pending", 0) + counts.get("downloading", 0),
        "max_concurrent": MAX_CONCURRENT_DOWNLOADS,
        "tasks": sorted(tasks, key=lambda t: t["age_seconds"], reverse=True),
    }


@app.delete("/api/admin/tasks/{task_id}")
def api_admin_delete_task(
    task_id: str,
    force: bool = False,
    auth=Depends(verify_admin),
):
    """Purge a single task and its temp folder."""
    with _tasks_lock:
        task = download_tasks.get(task_id)
        if not task:
            raise HTTPException(404, "Download task not found")
        if task.get("status") == "downloading" and not force:
            raise HTTPException(
                409,
                "Task is actively downloading. Use force=true to purge anyway.",
            )
        download_tasks.pop(task_id, None)
        folder = _task_folder(task_id, task)
    if folder:
        shutil.rmtree(folder, ignore_errors=True)
    _save_tasks()
    return {"status": "purged", "task_id": task_id}


class PurgeRequest(BaseModel):
    # Terminal tasks (completed/failed) older than this are purged.
    older_than_seconds: int = Field(default=300, ge=0)
    # Pending/downloading tasks older than this are considered stuck and purged.
    stuck_after_seconds: int = Field(default=1800, ge=0)


@app.post("/api/admin/tasks/purge")
def api_admin_purge(req: PurgeRequest, auth=Depends(verify_admin)):
    """Bulk-clean completed/failed tasks and stuck downloads."""
    now = time.time()
    purged: list[str] = []
    folders: list[str] = []
    with _tasks_lock:
        for task_id, task in list(download_tasks.items()):
            age = now - (task.get("created_at") or now)
            status = task.get("status")
            terminal = status in ("completed", "failed")
            if terminal and age >= req.older_than_seconds:
                purged.append(task_id)
            elif status in ("pending", "downloading") and age >= req.stuck_after_seconds:
                purged.append(task_id)
        for task_id in purged:
            task = download_tasks.pop(task_id)
            folder = _task_folder(task_id, task)
            if folder:
                folders.append(folder)
    for folder in folders:
        shutil.rmtree(folder, ignore_errors=True)
    _save_tasks()
    return {"status": "purged", "purged": len(purged), "task_ids": purged}


# ═══════════════════════════════════════════════════════
#  BILLING & USER ENDPOINTS
# ═══════════════════════════════════════════════════════

@app.get("/api/user/{user_id}/profile")
def api_get_user_profile(user_id: int, auth=Depends(verify_auth)):
    credits = user_config.get_user_credits(user_id)
    is_sub = user_config.is_subscription_active(user_id)
    expiry = user_config.get_subscription_expiry(user_id)
    return {
        "user_id": user_id,
        "credits": credits,
        "is_subscription_active": is_sub,
        "subscription_expires_at": expiry,
        "monthly_price_npr": MONTHLY_SUB_PRICE_NPR,
        "daily_reward": 2,
        "payment_methods": {
            "esewa": ESEWA_ID,
            "khalti": KHALTI_ID,
            "bank": BANK_DETAILS,
        },
    }


@app.post("/api/user/{user_id}/claim-daily")
def api_claim_daily_reward(user_id: int, auth=Depends(verify_auth)):
    result = user_config.claim_daily_reward(user_id)
    if not result["claimed"]:
        raise HTTPException(409, detail={
            "message": "Daily reward already claimed",
            **result,
        })
    return result

@app.post("/api/user/submit-payment")
async def api_submit_payment_receipt(
    user_id: int = Form(...),
    tx_id: str = Form(...),
    method: str = Form(...),
    receipt: UploadFile | None = File(None),
    auth=Depends(verify_auth),
):
    transaction = tx_id.strip()
    payment_method = method.strip().lower()
    if not transaction:
        raise HTTPException(400, "Transaction ID cannot be empty")
    if payment_method not in {"esewa", "khalti", "bank"}:
        raise HTTPException(400, "Unsupported payment method")
    receipt_path = None
    if receipt is not None:
        extension = os.path.splitext(receipt.filename or "")[1].lower()
        if extension not in {".jpg", ".jpeg", ".png", ".pdf"}:
            raise HTTPException(400, "Receipt must be JPG, PNG, or PDF")
        contents = await receipt.read(5 * 1024 * 1024 + 1)
        if len(contents) > 5 * 1024 * 1024:
            raise HTTPException(413, "Receipt must be 5 MB or smaller")
        receipt_dir = os.path.join(TEMP_FOLDER, "payment_receipts")
        os.makedirs(receipt_dir, exist_ok=True)
        receipt_name = f"{user_id}_{uuid.uuid4().hex}{extension}"
        receipt_path = os.path.join(receipt_dir, receipt_name)
        with open(receipt_path, "wb") as receipt_file:
            receipt_file.write(contents)
    payment = user_config.add_pending_payment(
        user_id,
        transaction,
        MONTHLY_SUB_PRICE_NPR,
        method=payment_method,
        receipt_path=receipt_path,
    )
    return {
        "status": "submitted",
        "message": "Payment submitted for admin review",
        "payment": payment,
    }



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
