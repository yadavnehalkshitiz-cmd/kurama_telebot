"""KuramaBot — Utility functions"""

import os
import re
import time
import asyncio
import logging
from datetime import datetime

from config import PLATFORM_RULES

logger = logging.getLogger(__name__)


# ─── Platform detection ─────────────────────────────────

def get_platform(url: str) -> tuple:
    """Detect platform from URL using regex rules. Returns (name, emoji)."""
    u = url.lower()
    for pattern, name, emoji in PLATFORM_RULES:
        if pattern.search(u):
            return name, emoji
    return "Other", "🔗"


# ─── Formatting helpers ─────────────────────────────────

def human_size(b):
    if b is None:
        return "Unknown"
    for unit in ["B", "KB", "MB", "GB"]:
        if b < 1024:
            return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} TB"


def human_duration(secs):
    if not secs:
        return "Unknown"
    m, s = divmod(int(secs), 60)
    h, m = divmod(m, 60)
    return f"{h}h {m}m {s}s" if h else f"{m}m {s}s"


def clean_md(text):
    """Strip markdown special chars so we can safely wrap in * or `."""
    if not text:
        return ""
    return str(text).replace("*", "").replace("_", "").replace("`", "").replace("[", "").replace("]", "")


def make_progress_bar(pct: float, width: int = 20) -> str:
    filled = int(pct / 100 * width)
    return "█" * filled + "░" * (width - filled)


def fmt_date(raw: str) -> str:
    if not raw:
        return "Unknown"
    try:
        return datetime.strptime(raw, "%Y%m%d").strftime("%d %b %Y")
    except ValueError:
        return raw


def shorten(text: str, max_len: int = 70) -> str:
    if len(text) <= max_len:
        return text
    return text[:max_len] + "…"


# ─── Rate‑limited progress hook factory ─────────────────

class ProgressTracker:
    """Thread‑safe progress tracker for rate‑limited UI updates."""

    def __init__(self, chat_id, platform, audio_only, loop, edit_callback, interval=2.5):
        self.chat_id = chat_id
        self.platform = platform
        self.audio_only = audio_only
        self.loop = loop
        self.edit = edit_callback
        self.interval = interval
        self.last_time = 0.0
        self.last_text = ""

    def __call__(self, d):
        if d["status"] != "downloading":
            return
        downloaded = d.get("downloaded_bytes", 0)
        total = d.get("total_bytes") or d.get("total_bytes_estimate", 0)
        speed = d.get("speed") or 0
        eta = d.get("eta") or 0
        content = "🎵 Audio" if self.audio_only else "🎬 Video"

        if total:
            pct = downloaded / total * 100
            bar = make_progress_bar(pct)
            speed_str = f"{human_size(speed)}/s" if speed else "?/s"
            new_text = (
                f"⬇️ *Downloading {content} from {self.platform}…*\n\n"
                f"`[{bar}]` {pct:.1f}%\n"
                f"📦 {human_size(downloaded)} / {human_size(total)}\n"
                f"⚡ {speed_str}  ⏱ ETA: {int(eta)}s"
            )
        else:
            new_text = (
                f"⬇️ *Downloading {content} from {self.platform}…*\n\n"
                f"📦 {human_size(downloaded)} downloaded"
            )

        now = time.time()
        if new_text != self.last_text and (now - self.last_time) > self.interval:
            self.last_text = new_text
            self.last_time = now
            asyncio.run_coroutine_threadsafe(
                self.edit(new_text),
                self.loop,
            )


# ─── FFmpeg path ────────────────────────────────────────

def get_ffmpeg_path():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if os.name == "nt":
        local = os.path.join(script_dir, "ffmpeg.exe")
        if os.path.exists(local):
            return local
    return "ffmpeg"
