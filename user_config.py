"""KuramaBot — Per‑user config persistence (custom folders, preferences)"""

import json
import os
import tempfile
import threading
from config import USER_CONFIGS_FILE

# Threading lock for atomic read/write of the config file.
# Safe for single-process multi-threaded access (asyncio.to_thread, daemon threads).
_file_lock = threading.Lock()


def load():
    with _file_lock:
        if os.path.exists(USER_CONFIGS_FILE):
            try:
                with open(USER_CONFIGS_FILE, "r", encoding="utf-8") as f:
                    return json.load(f)
            except (json.JSONDecodeError, OSError):
                # Corrupted file — start fresh rather than crash
                return {}
        return {}


def save(configs):
    """Atomically write configs: write to temp file, then os.replace."""
    with _file_lock:
        dir_name = os.path.dirname(USER_CONFIGS_FILE) or "."
        fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(configs, f, indent=2)
            os.replace(tmp_path, USER_CONFIGS_FILE)
        except Exception:
            # Clean up temp file if replace failed
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise


def get_custom_folder(chat_id: int) -> str | None:
    """Return custom folder for a chat, or None."""
    cfg = _configs.get(str(chat_id), {})
    return cfg.get("custom_folder")


def set_custom_folder(chat_id: int, folder: str):
    cid = str(chat_id)
    if cid not in _configs:
        _configs[cid] = {}
    _configs[cid]["custom_folder"] = folder
    save(_configs)


def reset_custom_folder(chat_id: int):
    cid = str(chat_id)
    if cid in _configs:
        _configs[cid].pop("custom_folder", None)
        if not _configs[cid]:
            del _configs[cid]
    save(_configs)


# ─── Queue support ──────────────────────────────────────

def get_queue(chat_id: int) -> list:
    return _configs.get(str(chat_id), {}).get("queue", [])


def set_queue(chat_id: int, queue: list):
    cid = str(chat_id)
    if cid not in _configs:
        _configs[cid] = {}
    _configs[cid]["queue"] = queue
    save(_configs)


def add_to_queue(chat_id: int, url: str):
    q = get_queue(chat_id)
    q.append(url)
    set_queue(chat_id, q)


def pop_queue(chat_id: int) -> str | None:
    q = get_queue(chat_id)
    if not q:
        return None
    url = q.pop(0)
    set_queue(chat_id, q)
    return url


def clear_queue(chat_id: int):
    set_queue(chat_id, [])


# ─── Module-level cache ─────────────────────────────────
# Loaded once at import. This is intentional for single-process bots —
# all mutations go through the functions above which update both
# the in-memory dict and the on-disk file atomically.
_configs = load()
