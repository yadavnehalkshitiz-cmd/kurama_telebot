"""
╔══════════════════════════════════╗
║     🦊 KuramaBot — Entry Point   ║
╚══════════════════════════════════╝

Multi‑platform video/audio downloader for Telegram.
Refactored into modules under the same directory.
"""

import os
import sys
import time
import logging
import socket
import urllib.request
import urllib.error

# Fix Windows terminal emoji encoding
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        try:
            sys.stdin.reconfigure(encoding="utf-8")
        except Exception:
            pass

from telegram.ext import (
    ApplicationBuilder,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    filters,
)

from config import TOKEN, LAPTOP_FOLDER
from handlers import (
    start,
    help_cmd,
    cookies_cmd,
    cancel_cmd,
    queue_cmd,
    setfolder_cmd,
    credits_cmd,
    buy_cmd,
    submitpayment_cmd,
    admin_cmd,
    grantpremium_cmd,
    setcredits_cmd,
    revokeplan_cmd,
    handle_message,
    handle_callback,
)

# ─── Logging ────────────────────────────────────────────
logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO,
    force=True,
)
logger = logging.getLogger(__name__)


# ─── Network wait (Docker / slow boot) ──────────────────

def wait_for_network():
    """Wait until both DNS *and* HTTP connectivity to Telegram are available."""
    check = "[NET] Checking network..."
    ok = "[NET] Network OK!"
    dns_wait = "[NET] DNS not ready yet, retrying in 5s…"
    http_wait = "[NET] API not reachable yet (HTTP), retrying in 5s…"
    print(check)
    backoff = 3
    while True:
        # 1. DNS check first
        try:
            socket.gethostbyname("api.telegram.org")
        except socket.gaierror:
            print(dns_wait)
            time.sleep(backoff)
            backoff = min(backoff + 2, 15)
            continue

        # 2. HTTP connectivity check (lightweight HEAD request)
        try:
            req = urllib.request.Request(
                "https://api.telegram.org/",
                method="HEAD",
                headers={"User-Agent": "KuramaBot/1.0"},
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                pass  # any 2xx / 3xx is fine
            print(ok)
            return
        except urllib.error.URLError as e:
            print(f"{http_wait} ({e.reason})")
            time.sleep(backoff)
            backoff = min(backoff + 2, 15)
        except Exception as e:
            print(f"[NET] Unexpected error: {e}, retrying in {backoff}s…")
            time.sleep(backoff)
            backoff = min(backoff + 2, 15)


# ─── Main ───────────────────────────────────────────────

def main():
    if not TOKEN:
        print("[ERR] TELEGRAM_BOT_TOKEN not set in .env file!")
        sys.exit(1)

    wait_for_network()

    app = ApplicationBuilder().token(TOKEN).build()

    # ── Commands ────────────────────────────────────────
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("credits", credits_cmd))
    app.add_handler(CommandHandler("buy", buy_cmd))
    app.add_handler(CommandHandler("submitpayment", submitpayment_cmd))
    # ── Admin commands (only works from ADMIN_CHAT_ID) ────
    app.add_handler(CommandHandler("admin", admin_cmd))
    app.add_handler(CommandHandler("grantpremium", grantpremium_cmd))
    app.add_handler(CommandHandler("setcredits", setcredits_cmd))
    app.add_handler(CommandHandler("revokeplan", revokeplan_cmd))
    app.add_handler(CommandHandler("cookies", cookies_cmd))
    app.add_handler(CommandHandler("cancel", cancel_cmd))
    app.add_handler(CommandHandler("queue", queue_cmd))
    app.add_handler(CommandHandler("setfolder", setfolder_cmd))

    # ── Messages (URLs) + Callbacks ─────────────────────
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    app.add_handler(CallbackQueryHandler(handle_callback))

    # ── Start ───────────────────────────────────────────
    from config import ADMIN_CHAT_ID, ESEWA_ID, INITIAL_FREE_CREDITS, MONTHLY_SUB_PRICE_NPR
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("🦊  KuramaBot starting up…")
    print(f"[BOT] Laptop downloads  → {LAPTOP_FOLDER}")
    print(f"[BOT] Free credits      → {INITIAL_FREE_CREDITS} per new user")
    print(f"[BOT] Subscription      → {MONTHLY_SUB_PRICE_NPR} NPR / month")
    if ADMIN_CHAT_ID:
        print(f"[BOT] Admin chat ID     → {ADMIN_CHAT_ID} ✅")
    else:
        print("[BOT] ⚠️  ADMIN_CHAT_ID not set — payment alerts DISABLED!")
        print("[BOT]    Set ADMIN_CHAT_ID=<your_telegram_id> in Render env vars.")
    if ESEWA_ID == "9800000000":
        print("[BOT] ⚠️  ESEWA_ID is still the placeholder — update in Render env vars!")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    app.run_polling(bootstrap_retries=5, drop_pending_updates=True)


if __name__ == "__main__":
    main()
