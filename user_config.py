"""KuramaBot — Per‑user config persistence (custom folders, preferences)"""

import json
import os
import tempfile
import threading
from datetime import datetime, timedelta, timezone
from config import USER_CONFIGS_FILE, INITIAL_FREE_CREDITS

# Threading lock for atomic read/write of the config file.
# Safe for single-process multi-threaded access (asyncio.to_thread, daemon threads).
_file_lock = threading.Lock()
_state_lock = threading.RLock()


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


# ─── Billing & Subscription System ─────────────────────

def _ensure_user_profile(chat_id: int) -> dict:
    """Ensure user entry exists with billing fields."""
    cid = str(chat_id)
    if cid not in _configs:
        _configs[cid] = {}
    
    cfg = _configs[cid]
    changed = False
    if "credits" not in cfg:
        cfg["credits"] = INITIAL_FREE_CREDITS
        changed = True
    if "subscription_expires_at" not in cfg:
        cfg["subscription_expires_at"] = None
        changed = True
    if "pending_payments" not in cfg:
        cfg["pending_payments"] = []
        changed = True
    if "last_daily_claim_at" not in cfg:
        cfg["last_daily_claim_at"] = None
        changed = True

    if changed:
        save(_configs)
    return cfg


def get_user_credits(chat_id: int) -> int:
    """Return remaining free credits for a user."""
    cfg = _ensure_user_profile(chat_id)
    return cfg.get("credits", INITIAL_FREE_CREDITS)


def is_subscription_active(chat_id: int) -> bool:
    """Check if the user has an active 30-day premium subscription."""
    cfg = _ensure_user_profile(chat_id)
    expiry_str = cfg.get("subscription_expires_at")
    if not expiry_str:
        return False
    try:
        expiry_dt = datetime.fromisoformat(expiry_str)
        now_dt = datetime.now(timezone.utc)
        return expiry_dt > now_dt
    except (ValueError, TypeError):
        return False


def get_subscription_expiry(chat_id: int) -> str | None:
    """Return ISO format string of subscription expiry, or None."""
    cfg = _ensure_user_profile(chat_id)
    return cfg.get("subscription_expires_at")


def deduct_credit(chat_id: int) -> bool:
    """
    Deduct 1 credit if user is not on an active subscription.
    Returns True if deduction succeeded or user has active sub, False if 0 credits.
    """
    if is_subscription_active(chat_id):
        return True
    
    cfg = _ensure_user_profile(chat_id)
    current_credits = cfg.get("credits", 0)
    if current_credits > 0:
        cfg["credits"] = current_credits - 1
        save(_configs)
        return True
    return False


def consume_download_credit(chat_id: int) -> tuple[bool, bool]:
    """Atomically authorize a download and report whether a credit was charged."""
    with _state_lock:
        if is_subscription_active(chat_id):
            return True, False
        cfg = _ensure_user_profile(chat_id)
        credits = int(cfg.get("credits", 0))
        if credits <= 0:
            return False, False
        cfg["credits"] = credits - 1
        save(_configs)
        return True, True


def refund_credit(chat_id: int) -> int:
    """Refund one credit after a server-side download failure."""
    with _state_lock:
        cfg = _ensure_user_profile(chat_id)
        cfg["credits"] = int(cfg.get("credits", 0)) + 1
        save(_configs)
        return cfg["credits"]


def claim_daily_reward(
    chat_id: int,
    *,
    now: datetime | None = None,
    amount: int = 2,
) -> dict:
    """Grant a rolling 24-hour reward exactly once per eligibility window."""
    with _state_lock:
        current = now or datetime.now(timezone.utc)
        if current.tzinfo is None:
            current = current.replace(tzinfo=timezone.utc)
        cfg = _ensure_user_profile(chat_id)
        last_value = cfg.get("last_daily_claim_at")
        if last_value:
            try:
                last = datetime.fromisoformat(last_value)
                next_claim = last + timedelta(hours=24)
                if current < next_claim:
                    return {
                        "claimed": False,
                        "credits": int(cfg.get("credits", 0)),
                        "next_claim_at": next_claim.isoformat(),
                    }
            except (TypeError, ValueError):
                pass
        cfg["credits"] = int(cfg.get("credits", 0)) + amount
        cfg["last_daily_claim_at"] = current.isoformat()
        save(_configs)
        return {
            "claimed": True,
            "reward": amount,
            "credits": cfg["credits"],
            "next_claim_at": (current + timedelta(hours=24)).isoformat(),
        }


def grant_subscription(chat_id: int, days: int = 30):
    """Grant or extend a user's premium subscription by `days` days."""
    cfg = _ensure_user_profile(chat_id)
    now = datetime.now(timezone.utc)
    
    current_expiry_str = cfg.get("subscription_expires_at")
    if current_expiry_str:
        try:
            curr_expiry = datetime.fromisoformat(current_expiry_str)
            if curr_expiry > now:
                new_expiry = curr_expiry + timedelta(days=days)
            else:
                new_expiry = now + timedelta(days=days)
        except (ValueError, TypeError):
            new_expiry = now + timedelta(days=days)
    else:
        new_expiry = now + timedelta(days=days)
        
    cfg["subscription_expires_at"] = new_expiry.isoformat()
    save(_configs)
    return new_expiry.isoformat()


def add_pending_payment(
    chat_id: int,
    tx_id: str,
    amount: int = 500,
    *,
    method: str = "other",
    receipt_path: str | None = None,
) -> dict:
    """Record a pending payment for admin review."""
    cfg = _ensure_user_profile(chat_id)
    payment = {
        "tx_id": tx_id.strip(),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "amount": amount,
        "status": "PENDING",
        "method": method,
        "receipt_path": receipt_path,
    }
    cfg["pending_payments"].append(payment)
    save(_configs)
    return payment


def update_payment_status(chat_id: int, tx_id: str, status: str) -> bool:
    """Update status of a transaction (APPROVED / REJECTED)."""
    cfg = _ensure_user_profile(chat_id)
    updated = False
    for p in cfg.get("pending_payments", []):
        if p.get("tx_id") == tx_id.strip() and p.get("status") == "PENDING":
            p["status"] = status.upper()
            updated = True
            break
    if updated:
        save(_configs)
    return updated


# ─── Module-level cache ─────────────────────────────────
# Loaded once at import. This is intentional for single-process bots —
# all mutations go through the functions above which update both
# the in-memory dict and the on-disk file atomically.
_configs = load()


# ─── Admin helpers ──────────────────────────────────────

def get_all_users() -> list[dict]:
    """Return a summary list of all known users for admin overview."""
    now = datetime.now(timezone.utc)
    result = []
    for cid, cfg in _configs.items():
        expiry_str = cfg.get("subscription_expires_at")
        active = False
        if expiry_str:
            try:
                active = datetime.fromisoformat(expiry_str) > now
            except (ValueError, TypeError):
                pass
        pending = [p for p in cfg.get("pending_payments", []) if p.get("status") == "PENDING"]
        result.append({
            "chat_id": cid,
            "credits": cfg.get("credits", INITIAL_FREE_CREDITS),
            "subscription_active": active,
            "subscription_expires_at": expiry_str,
            "pending_payment_count": len(pending),
        })
    return result


def get_pending_payments() -> list[dict]:
    """Return all PENDING payments across all users."""
    pending = []
    for cid, cfg in _configs.items():
        for p in cfg.get("pending_payments", []):
            if p.get("status") == "PENDING":
                pending.append({"chat_id": cid, **p})
    return pending


def admin_set_credits(chat_id: int, credits: int):
    """Manually set a user's free credits (admin action)."""
    cfg = _ensure_user_profile(chat_id)
    cfg["credits"] = max(0, credits)
    save(_configs)


def admin_revoke_subscription(chat_id: int):
    """Immediately revoke a user's subscription (admin action)."""
    cfg = _ensure_user_profile(chat_id)
    cfg["subscription_expires_at"] = None
    save(_configs)


def get_stats() -> dict:
    """Return high-level stats for admin dashboard."""
    now = datetime.now(timezone.utc)
    total = len(_configs)
    active_subs = 0
    zero_credits = 0
    pending_payments = 0
    for cfg in _configs.values():
        expiry_str = cfg.get("subscription_expires_at")
        if expiry_str:
            try:
                if datetime.fromisoformat(expiry_str) > now:
                    active_subs += 1
            except (ValueError, TypeError):
                pass
        if cfg.get("credits", INITIAL_FREE_CREDITS) <= 0 and not expiry_str:
            zero_credits += 1
        pending_payments += sum(
            1 for p in cfg.get("pending_payments", []) if p.get("status") == "PENDING"
        )
    return {
        "total_users": total,
        "active_subscribers": active_subs,
        "free_tier_exhausted": zero_credits,
        "pending_payments": pending_payments,
    }
