"""KuramaBot — All command & callback handlers"""

import os
import time
import logging
import asyncio
import ipaddress
from urllib.parse import urlparse

from telegram import Update
from telegram.ext import ContextTypes

import config
from config import LAPTOP_FOLDER, TEMP_FOLDER, COOKIES_FOLDER, MAX_URL_LENGTH
import utils
from utils import (
    get_platform,
    human_size,
    human_duration,
    clean_md,
    make_progress_bar,
    fmt_date,
    shorten,
    ProgressTracker,
)
import user_config
from user_config import get_custom_folder, set_custom_folder, reset_custom_folder
import downloader
from downloader import get_cookie_file, build_ydl_opts, fetch_info, download_single
import senders
from senders import send_video, send_audio, send_document
import keyboards
from keyboards import (
    format_picker,
    video_quality_picker,
    audio_quality_picker,
    destination_picker,
    playlist_actions,
    setfolder_confirm,
    buy_subscription_keyboard,
    admin_payment_approval_keyboard,
)

logger = logging.getLogger(__name__)

# ─── Session state ──────────────────────────────────────
# { chat_id: { 'url', 'title', 'platform', 'icon', 'format', 'video_quality',
#              'audio_quality', 'destination', 'filepath', 'thumb_path',
#              'playlist', 'playlist_entries' } }
sessions = {}

# { chat_id: [url, ...] }
# Download queue: URLs waiting to be processed
queues = {}

# Lock per chat to prevent concurrent downloads
active_downloads = set()

# Async lock to guard session/active_downloads mutations
_state_lock = asyncio.Lock()


# ═══════════════════════════════════════════════════════
#  COMMANDS
# ═══════════════════════════════════════════════════════

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user.first_name
    chat_id = update.effective_chat.id
    credits = user_config.get_user_credits(chat_id)
    is_sub = user_config.is_subscription_active(chat_id)

    tier_msg = "⭐ *KuramaBot Premium* (Unlimited)" if is_sub else f"🎟️ *Free Tier:* `{credits}` free credits left"

    await update.message.reply_text(
        f"👋 *Hello {user}!* I'm KuramaBot 🦊\n\n"
        f"{tier_msg}\n\n"
        "📎 Send me any link and I'll help you download it.\n\n"
        "‣ *Choose format*: 🎬 Video · 🎵 Audio · 📄 File (no re-encode)\n"
        "‣ *Choose quality*: Best · 1080p · 720p · 480p\n"
        "‣ *Choose destination*: 💻 Laptop · 📱 Telegram\n\n"
        "💳 *Buy Premium:* `/buy` (500 NPR/mo)\n"
        "📊 *Check Balance:* `/credits`\n"
        "📂 *Custom folder:* `/setfolder C:\\\\path\\\\to\\\\folder`\n"
        "📋 *Queue:* Send multiple URLs, they'll download one by one\n\n"
        "🌐 YouTube · Instagram · TikTok · Facebook · Twitter/X\n"
        "      Reddit · Pinterest · Threads · Vimeo & more!\n\n"
        "👇 _Paste a link to get started._",
        parse_mode="Markdown",
    )


async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "*📖 KuramaBot Help*\n\n"
        "*Flow:*\n"
        "1. Paste a URL → I show video info with thumbnail\n"
        "2. Pick *format*: 🎬 Video / 🎵 Audio / 📄 File\n"
        "3. Pick *quality*: Best · 1080p · 720p · 480p\n"
        "4. Pick *destination*: 💻 Laptop · 📱 Telegram\n\n"
        "*Credits & Premium:*\n"
        "Every user gets **3 free credits**. Premium costs **500 NPR/mo** for unlimited downloads.\n\n"
        "*Commands:*\n"
        "  /start   — Welcome\n"
        "  /credits — View free credits & subscription status\n"
        "  /buy     — Buy 1 Month Premium (500 NPR)\n"
        "  /submitpayment <tx_id> — Submit transaction code\n"
        "  /help    — Help menu\n"
        "  /cookies — Cookie setup guide\n"
        "  /setfolder — Custom download folder\n"
        "  /queue   — View download queue\n"
        "  /cancel  — Cancel current operation\n",
        parse_mode="Markdown",
    )


async def credits_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    credits = user_config.get_user_credits(chat_id)
    is_sub = user_config.is_subscription_active(chat_id)
    expiry = user_config.get_subscription_expiry(chat_id)

    if is_sub:
        exp_date = expiry[:10] if expiry else "N/A"
        sub_status = f"✅ *ACTIVE (Unlimited Downloads)*\n📅 *Expires:* `{exp_date}`"
    else:
        sub_status = f"❌ *Inactive (Free Tier)*\n🎟️ *Free Credits Remaining:* `{credits}` / 3"

    await update.message.reply_text(
        f"📊 *Your KuramaBot Plan & Credits*\n\n"
        f"{sub_status}\n\n"
        f"💳 Premium Subscription: *500 NPR / month*\n"
        f"Includes unlimited video and audio downloads!",
        parse_mode="Markdown",
        reply_markup=keyboards.buy_subscription_keyboard(),
    )


async def buy_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        f"⭐ *KuramaBot Premium Subscription* ⭐\n\n"
        f"Get *unlimited downloads* for *500 NPR / month*!\n\n"
        f"📌 *Payment Options (Nepal):*\n"
        f"{config.BANK_DETAILS}\n\n"
        f"📝 *How to Activate:* \n"
        f"1️⃣ Transfer **500 NPR** via eSewa / Khalti / Bank.\n"
        f"2️⃣ Copy your **Transaction ID / Reference Code**.\n"
        f"3️⃣ Send command `/submitpayment <tx_id>` in this chat!\n"
        f"    _(Example: `/submitpayment 987654321`)_\n\n"
        f"⏳ Your subscription will be activated upon admin confirmation.",
        parse_mode="Markdown",
    )


async def submitpayment_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    user = update.effective_user

    if not context.args:
        await update.message.reply_text(
            "⚠️ Please provide your payment Transaction ID.\n"
            "Example: `/submitpayment 987654321`",
            parse_mode="Markdown",
        )
        return

    tx_id = " ".join(context.args).strip()
    user_config.add_pending_payment(chat_id, tx_id, amount=config.MONTHLY_SUB_PRICE_NPR)

    await update.message.reply_text(
        f"✅ *Payment Submitted for Review!*\n\n"
        f"🆔 *Transaction ID:* `{tx_id}`\n"
        f"💰 *Amount:* 500 NPR\n\n"
        f"⏳ Your subscription will be activated upon admin confirmation.",
        parse_mode="Markdown",
    )

    if config.ADMIN_CHAT_ID:
        try:
            admin_text = (
                f"💳 *NEW PAYMENT SUBMISSION*\n\n"
                f"👤 *User:* [{clean_md(user.first_name)}](tg://user?id={chat_id}) (`{chat_id}`)\n"
                f"🆔 *Tx ID:* `{clean_md(tx_id)}`\n"
                f"💵 *Amount:* 500 NPR\n"
                f"📅 *Time:* `{time.strftime('%Y-%m-%d %H:%M:%S')}`"
            )
            await context.bot.send_message(
                chat_id=config.ADMIN_CHAT_ID,
                text=admin_text,
                parse_mode="Markdown",
                reply_markup=keyboards.admin_payment_approval_keyboard(chat_id, tx_id),
            )
        except Exception as e:
            logger.error(f"Failed to send admin notification: {e}")



async def cookies_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cookies_path = COOKIES_FOLDER
    platforms = ["instagram", "youtube", "twitter", "facebook", "tiktok", "reddit"]
    lines = []
    for p in platforms:
        path = os.path.join(cookies_path, f"{p}.txt")
        icon = "✅" if os.path.exists(path) else "❌"
        lines.append(f"  {icon} `{p}.txt`")

    await update.message.reply_text(
        "*🍪 Cookie Setup Guide*\n\n"
        "Some platforms (Instagram, Twitter/X, Facebook) need login cookies.\n\n"
        "─────────────────────\n"
        "*Current status:*\n"
        f"{chr(10).join(lines)}\n\n"
        "─────────────────────\n"
        "*How-to:*\n"
        "1. Install *Get cookies.txt LOCALLY* Chrome extension\n"
        "2. Log in to the platform in Chrome\n"
        "3. Export cookies, save to:\n"
        f"   `{cookies_path}`\n"
        "   Filename: `instagram.txt`, `twitter.txt`, etc.\n"
        "4. Restart the bot ✅\n\n"
        "_Cookies stay on your laptop, never shared._",
        parse_mode="Markdown",
    )


async def cancel_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cid = update.effective_chat.id
    cleared = False
    async with _state_lock:
        if cid in sessions:
            # Clean up any temp thumbnail
            thumb = sessions[cid].get("thumb_path")
            if thumb and os.path.exists(thumb):
                try:
                    os.remove(thumb)
                except OSError:
                    pass
            del sessions[cid]
            cleared = True
        if cid in queues:
            user_config.set_queue(cid, [])
            queues.pop(cid, None)
            cleared = True
        if cid in active_downloads:
            active_downloads.discard(cid)
            cleared = True

    if cleared:
        await update.message.reply_text("✅ Operation cancelled and queue cleared.")
    else:
        await update.message.reply_text("Nothing to cancel.")


async def queue_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cid = update.effective_chat.id
    q = user_config.get_queue(cid)
    if not q:
        await update.message.reply_text("📋 *Queue is empty.*", parse_mode="Markdown")
        return
    lines = [f"{i+1}. `{url[:60]}…`" for i, url in enumerate(q[:10])]
    if len(q) > 10:
        lines.append(f"… and {len(q) - 10} more")
    await update.message.reply_text(
        f"📋 *Download Queue ({len(q)} pending)*\n\n" + "\n".join(lines),
        parse_mode="Markdown",
    )


async def setfolder_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cid = update.effective_chat.id
    args = context.args

    if not args:
        current = user_config.get_custom_folder(cid) or "Not set"
        await update.message.reply_text(
            f"📂 *Current custom folder:* `{current}`\n\n"
            "*Usage:* `/setfolder C:\\\\path\\\\to\\\\folder`\n"
            "`/setfolder default` — reset to default\n\n"
            "_Used when you download to 💻 Laptop._",
            parse_mode="Markdown",
        )
        return

    folder = " ".join(args).strip()

    if folder.lower() == "default":
        user_config.reset_custom_folder(cid)
        await update.message.reply_text(
            f"✅ *Reset to default folder.*\n📁 `{LAPTOP_FOLDER}`",
            parse_mode="Markdown",
        )
        return

    folder = os.path.abspath(folder)
    if not os.path.exists(folder):
        # Store pending for mkdir confirmation
        context.chat_data["pending_folder"] = folder
        await update.message.reply_text(
            f"📂 Folder doesn't exist:\n`{folder}`\n\nCreate it?",
            parse_mode="Markdown",
            reply_markup=setfolder_confirm(),
        )
        return

    user_config.set_custom_folder(cid, folder)
    await update.message.reply_text(
        f"✅ *Custom folder set!*\n📁 `{folder}`",
        parse_mode="Markdown",
    )


# ═══════════════════════════════════════════════════════
#  MESSAGE HANDLER  (URL → info + format picker)
# ═══════════════════════════════════════════════════════

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    url = update.message.text.strip()
    chat_id = update.effective_chat.id

    if not url.startswith(("http://", "https://")):
        await update.message.reply_text(
            "⚠️ Please send a valid URL starting with `http://` or `https://`",
            parse_mode="Markdown",
        )
        return

    # Input length validation
    if len(url) > MAX_URL_LENGTH:
        await update.message.reply_text(
            f"⚠️ URL is too long (max {MAX_URL_LENGTH} characters).",
            parse_mode="Markdown",
        )
        return

    platform, icon = get_platform(url)

    status = await update.message.reply_text(
        f"{icon} *Fetching info from {platform}…*",
        parse_mode="Markdown",
    )

    # ── Fetch info ──────────────────────────────────────
    try:
        info = await asyncio.to_thread(fetch_info, url, platform)
    except Exception as e:
        logger.error(f"Fetch info failed [{platform}]: {e}")
        await status.edit_text(
            f"❌ *Could not fetch info.*\n`{str(e)[:200]}`",
            parse_mode="Markdown",
        )
        return

    # ── Check if playlist ───────────────────────────────
    entries = info.get("entries")
    # yt-dlp can return a lazy generator — materialize it
    if entries is not None:
        entries = list(entries)
    is_playlist_result = entries is not None and len(entries) > 1

    # ── Parse info ──────────────────────────────────────
    title = clean_md(info.get("title") or info.get("webpage_title", "Unknown Title"))
    duration = info.get("duration")
    uploader = clean_md(info.get("uploader") or info.get("channel", "Unknown"))
    filesize = info.get("filesize_approx") or info.get("filesize")
    views = info.get("view_count")
    upload_date = fmt_date(info.get("upload_date"))
    extractor = info.get("extractor_key", "")

    views_str = f"{views:,}" if views else "N/A"

    # Try to download thumbnail (non-blocking, SSRF-safe)
    thumb_path = None
    thumbnail_url = info.get("thumbnail")
    if thumbnail_url and _is_safe_thumbnail_url(thumbnail_url):
        try:
            thumb_path = await asyncio.to_thread(
                _download_thumbnail_sync, chat_id, thumbnail_url
            )
        except Exception as e:
            logger.debug(f"Thumbnail download failed: {e}")

    # ── Store session ───────────────────────────────────
    async with _state_lock:
        sessions[chat_id] = {
            "url": url,
            "title": title,
            "platform": platform,
            "icon": icon,
            "thumb_path": thumb_path,
            "playlist": is_playlist_result,
            "playlist_entries": entries if is_playlist_result else None,
            "extractor": extractor,
        }

    # ── Build info caption ──────────────────────────────
    dur_str = human_duration(duration)
    size_str = human_size(filesize)

    if is_playlist_result:
        video_count = len(entries)
        caption = (
            f"📋 *Playlist detected!*\n\n"
            f"{icon} **{shorten(title)}**\n"
            f"👤 {uploader}\n"
            f"📹 {video_count} videos  ⏱ {dur_str}\n\n"
            f"━━━━━━━━━━━━━━━━━━\n"
            f"What do you want to do?"
        )
        keyboard = playlist_actions()
    else:
        caption = (
            f"{icon} *{platform}*\n\n"
            f"📌 *{shorten(title)}*\n"
            f"👤 {uploader}\n"
            f"⏱ {dur_str}  📦 {size_str}\n"
            f"👁 {views_str} views  📅 {upload_date}\n\n"
            f"━━━━━━━━━━━━━━━━━━\n"
            f"Choose format:"
        )
        keyboard = format_picker()

    # ── Send ────────────────────────────────────────────
    try:
        if thumb_path and os.path.exists(thumb_path):
            await status.delete()
            with open(thumb_path, "rb") as f:
                await context.bot.send_photo(
                    chat_id=chat_id,
                    photo=f,
                    caption=caption,
                    parse_mode="Markdown",
                    reply_markup=keyboard,
                )
        else:
            await status.edit_text(caption, parse_mode="Markdown", reply_markup=keyboard)
    except Exception as e:
        logger.debug(f"Failed to send with thumbnail, falling back: {e}")
        await status.edit_text(caption, parse_mode="Markdown", reply_markup=keyboard)


# ═══════════════════════════════════════════════════════
#  CALLBACK HANDLER
# ═══════════════════════════════════════════════════════

async def handle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    chat_id = query.message.chat_id
    data = query.data

    # ── Cancel ──────────────────────────────────────────
    if data == "cancel":
        async with _state_lock:
            _cleanup_session(chat_id)
        await _safe_edit(query, "❌ *Cancelled.*")
        return

    # ── Billing & Payment callbacks ─────────────────────
    if data == "buy_info":
        await _safe_edit(
            query,
            f"⭐ *KuramaBot Premium (500 NPR / mo)* ⭐\n\n"
            f"📌 *Payment Options (Nepal):*\n"
            f"{config.BANK_DETAILS}\n\n"
            f"📝 Send `/submitpayment <tx_id>` to activate!",
            reply_markup=buy_subscription_keyboard(),
        )
        return

    if data == "check_credits":
        credits = user_config.get_user_credits(chat_id)
        is_sub = user_config.is_subscription_active(chat_id)
        expiry = user_config.get_subscription_expiry(chat_id)
        if is_sub:
            msg = f"✅ *Subscription Active*\n📅 Expires: `{expiry[:10] if expiry else 'N/A'}`"
        else:
            msg = f"🎟️ *Free Credits Remaining:* `{credits}` / 3"
        await _safe_edit(query, f"📊 *Status:* {msg}", reply_markup=buy_subscription_keyboard())
        return

    if data.startswith("pay_approve_"):
        parts = data.split("_")
        target_user = int(parts[2])
        tx_id = "_".join(parts[3:])
        user_config.update_payment_status(target_user, tx_id, "APPROVED")
        exp = user_config.grant_subscription(target_user, days=30)
        exp_str = exp[:10] if exp else "N/A"
        await _safe_edit(query, f"✅ *PAYMENT APPROVED*\nUser `{target_user}` active until `{exp_str}`.")
        try:
            await context.bot.send_message(
                chat_id=target_user,
                text=f"🎉 *Payment Approved!*\n\nYour KuramaBot Premium subscription is now **ACTIVE** until `{exp_str}`! Enjoy unlimited downloads. 🚀",
                parse_mode="Markdown",
            )
        except Exception as e:
            logger.error(f"Failed to notify user {target_user}: {e}")
        return

    if data.startswith("pay_reject_"):
        parts = data.split("_")
        target_user = int(parts[2])
        tx_id = "_".join(parts[3:])
        user_config.update_payment_status(target_user, tx_id, "REJECTED")
        await _safe_edit(query, f"❌ *PAYMENT REJECTED*\nTx `{tx_id}` rejected for user `{target_user}`.")
        try:
            await context.bot.send_message(
                chat_id=target_user,
                text=f"❌ *Payment Verification Failed*\n\nYour transaction `{tx_id}` could not be verified. Please check the ID or contact support.",
                parse_mode="Markdown",
            )
        except Exception as e:
            logger.error(f"Failed to notify user {target_user}: {e}")
        return

    # ── Mkdir callbacks ─────────────────────────────────
    if data == "mkdir_yes":
        await _handle_mkdir_yes(query, context, chat_id)
        return
    if data == "mkdir_no":
        context.chat_data.pop("pending_folder", None)
        await _safe_edit(query, "❌ Folder creation cancelled.")
        return

    # ── Queue next ──────────────────────────────────────
    if data == "queue_next":
        await _process_queue(chat_id, query, context)
        return

    # ── Format selection ────────────────────────────────
    if data.startswith("fmt_"):
        await _handle_format(query, chat_id, data)
        return

    # ── Video quality selection ─────────────────────────
    if data.startswith("vq_"):
        await _handle_video_quality(query, chat_id, data)
        return

    # ── Audio quality selection ─────────────────────────
    if data.startswith("aq_"):
        await _handle_audio_quality(query, chat_id, data)
        return

    # ── Destination selection ───────────────────────────
    if data.startswith("dest_"):
        await _handle_destination(query, chat_id, data, context)
        return

    # ── Playlist actions ────────────────────────────────
    if data.startswith("pl_"):
        await _handle_playlist(query, chat_id, data, context)
        return

    # ── Back navigation ─────────────────────────────────
    if data == "back_to_format":
        await _show_format_picker(query, chat_id)
        return
    if data == "back_to_quality":
        sess = sessions.get(chat_id)
        if sess:
            fmt = sess.get("format", "video")
            if fmt == "audio":
                await _show_audio_quality(query, chat_id)
            else:
                await _show_video_quality(query, chat_id)
        return


# ═══════════════════════════════════════════════════════
#  INTERNAL HANDLERS
# ═══════════════════════════════════════════════════════

async def _handle_mkdir_yes(query, context, chat_id):
    folder = context.chat_data.pop("pending_folder", None)
    if not folder:
        await _safe_edit(query, "⚠️ No folder pending. Try `/setfolder` again.")
        return
    try:
        os.makedirs(folder, exist_ok=True)
        user_config.set_custom_folder(chat_id, folder)
        await _safe_edit(query, f"✅ *Folder created!*\n📁 `{folder}`")
    except Exception as e:
        logger.error(f"mkdir failed for {folder}: {e}")
        await _safe_edit(query, f"❌ *Error:* `{str(e)[:200]}`")


async def _handle_format(query, chat_id, data):
    """User picked a format type (video / audio / doc / playlist)."""
    sess = sessions.get(chat_id)
    if not sess:
        await _safe_edit(query, "⚠️ Session expired. Send the link again.")
        return

    fmt_map = {
        "fmt_video": "video",
        "fmt_audio": "audio",
        "fmt_doc": "doc",
    }
    fmt = fmt_map.get(data)
    if not fmt:
        await _safe_edit(query, "⚠️ Unknown format.")
        return

    sess["format"] = fmt

    if fmt == "video":
        await _show_video_quality(query, chat_id)
    elif fmt == "audio":
        await _show_audio_quality(query, chat_id)
    elif fmt == "doc":
        # Document: no quality choice, go straight to destination
        await _show_destination(query, chat_id, video=False, audio=False, doc=True)


async def _show_video_quality(query, chat_id):
    s = sessions.get(chat_id)
    if not s:
        return
    title = shorten(s["title"], 50)
    await _safe_edit(
        query,
        f"🎬 *Video Quality*\n\n📌 {title}\n\nChoose quality:",
        reply_markup=video_quality_picker(),
    )


async def _show_audio_quality(query, chat_id):
    s = sessions.get(chat_id)
    if not s:
        return
    title = shorten(s["title"], 50)
    await _safe_edit(
        query,
        f"🎵 *Audio Bitrate*\n\n📌 {title}\n\nChoose quality:",
        reply_markup=audio_quality_picker(),
    )


async def _handle_video_quality(query, chat_id, data):
    sess = sessions.get(chat_id)
    if not sess:
        return
    quality = data.split("_", 1)[1]  # "best", "1080p", etc.
    sess["video_quality"] = quality
    await _show_destination(query, chat_id, video=True)


async def _handle_audio_quality(query, chat_id, data):
    sess = sessions.get(chat_id)
    if not sess:
        return
    quality = data.split("_", 1)[1]  # "best", "320k", etc.
    sess["audio_quality"] = quality
    await _show_destination(query, chat_id, audio=True)


async def _show_destination(query, chat_id, video=False, audio=False, doc=False):
    s = sessions.get(chat_id)
    if not s:
        return
    title = shorten(s["title"], 50)
    fmt_label = {"video": "🎬 Video", "audio": "🎵 Audio", "doc": "📄 File"}.get(
        s.get("format", "video"), "🎬 Video"
    )
    q_label = s.get("video_quality") or s.get("audio_quality") or "best"

    await _safe_edit(
        query,
        f"📥 *Where to save?*\n\n"
        f"{fmt_label} · `{q_label}`\n"
        f"📌 {title}\n\n"
        f"Choose destination:",
        reply_markup=destination_picker(video=video, audio=audio, doc=doc),
    )


async def _handle_destination(query, chat_id, data, context):
    """User picked a destination → start download."""
    sess = sessions.get(chat_id)
    if not sess:
        await _safe_edit(query, "⚠️ Session expired.")
        return

    dest_map = {
        "dest_laptop": "laptop",
        "dest_mobile": "mobile",
        "dest_both": "both",
    }
    dest = dest_map.get(data)
    if not dest:
        await _safe_edit(query, "⚠️ Unknown destination.")
        return

    sess["destination"] = dest

    # ── Check/start queue ───────────────────────────────
    async with _state_lock:
        if chat_id in active_downloads:
            # Already downloading — add to queue
            q = user_config.get_queue(chat_id)
            user_config.add_to_queue(chat_id, sess["url"])
            await _safe_edit(query, f"📋 *Added to queue.* Position: #{len(q)+1}")
            return

    await _run_download(chat_id, query, context)


async def _run_download(chat_id, query, context):
    """Execute the download for the current session."""
    sess = sessions.get(chat_id)
    if not sess:
        return

    # ── Check billing / credits ─────────────────────────
    if not user_config.is_subscription_active(chat_id) and user_config.get_user_credits(chat_id) <= 0:
        await _safe_edit(
            query,
            "🔒 *Free Download Limit Reached!*\n\n"
            "You have used all **3 free credits**.\n"
            "Upgrade to **KuramaBot Premium** for only **500 NPR / month** to get unlimited downloads!",
            reply_markup=buy_subscription_keyboard(),
        )
        _cleanup_session(chat_id)
        return

    # Deduct credit for free tier user
    user_config.deduct_credit(chat_id)

    async with _state_lock:
        active_downloads.add(chat_id)

    url = sess["url"]
    title = sess["title"]
    platform = sess["platform"]
    icon = sess["icon"]
    fmt = sess.get("format", "video")
    dest = sess.get("destination", "laptop")
    audio_only = fmt == "audio"
    send_as_doc = fmt == "doc"
    video_quality = sess.get("video_quality", "best")
    audio_quality = sess.get("audio_quality", "best")
    for_mobile = dest == "mobile"
    playlist_mode = sess.get("playlist_mode", False)

    # ── Save folder ─────────────────────────────────────
    if for_mobile:
        save_folder = TEMP_FOLDER
    elif audio_only:
        custom = user_config.get_custom_folder(chat_id)
        save_folder = custom or os.path.join(LAPTOP_FOLDER, "Audio")
    elif send_as_doc:
        custom = user_config.get_custom_folder(chat_id)
        save_folder = custom or os.path.join(LAPTOP_FOLDER, "Documents")
    else:
        custom = user_config.get_custom_folder(chat_id)
        save_folder = custom or os.path.join(LAPTOP_FOLDER, platform)
    os.makedirs(save_folder, exist_ok=True)

    # ── Progress hook ───────────────────────────────────
    loop = asyncio.get_running_loop()

    async def edit_msg(text, **kw):
        try:
            if query.message and (query.message.photo or query.message.video or query.message.document or query.message.audio or query.message.animation):
                await query.edit_message_caption(caption=text, parse_mode="Markdown", **kw)
            else:
                await query.edit_message_text(text, parse_mode="Markdown", **kw)
        except Exception as e:
            logger.debug(f"edit_msg failed: {e}")

    tracker = ProgressTracker(chat_id, platform, audio_only, loop, edit_msg)
    ydl_opts = build_ydl_opts(
        save_folder=save_folder,
        platform=platform,
        progress_hook=tracker,
        for_mobile=for_mobile,
        audio_only=audio_only,
        send_as_doc=send_as_doc,
        video_quality=video_quality,
        audio_quality=audio_quality,
        playlist_mode=playlist_mode,
    )

    # ── Initial status ──────────────────────────────────
    content_type = "🎵 Audio" if audio_only else ("📄 File" if send_as_doc else "🎬 Video")
    await edit_msg(
        f"⬇️ *Downloading {content_type} from {platform}…*\n"
        f"📍 Destination: {dest}\n\n"
        f"`[{make_progress_bar(0)}]` 0%\n_(Starting…)_"
    )

    # ── Download ────────────────────────────────────────
    try:
        filepath, info = await asyncio.to_thread(download_single, url, ydl_opts)
        sess["filepath"] = filepath
        file_size = os.path.getsize(filepath) if os.path.exists(filepath) else 0
    except Exception as e:
        logger.error(f"Download error [{platform}]: {e}")
        await _show_download_error(query, chat_id, platform, e)
        async with _state_lock:
            active_downloads.discard(chat_id)
            _cleanup_session(chat_id)
        return

    # ── Post-download actions ───────────────────────────
    try:
        if dest == "laptop":
            await _handle_laptop_done(query, chat_id, title, filepath, file_size, audio_only)
        elif dest == "mobile":
            await _handle_mobile_done(query, context, chat_id, title, filepath, icon, audio_only, send_as_doc)
        elif dest == "both":
            await _handle_both_done(query, context, chat_id, title, filepath, icon)
    except Exception as e:
        logger.error(f"Post-download error: {e}")
        await edit_msg(f"⚠️ *Downloaded but error:* `{str(e)[:200]}`\n💾 File: `{filepath}`")

    # ── Clean current session ───────────────────────────
    sess.pop("filepath", None)  # keep other info for now
    async with _state_lock:
        active_downloads.discard(chat_id)

    # ── Check queue ─────────────────────────────────────
    await _process_queue(chat_id, query, context)


# ─── Post-download helpers ──────────────────────────────

async def _handle_laptop_done(query, chat_id, title, filepath, file_size, audio_only):
    label = "🎵 Audio" if audio_only else "🎬 Video"
    await _safe_edit(query,
        f"✅ *{label} saved to Laptop!*\n\n"
        f"📌 *{shorten(title, 60)}*\n"
        f"📦 Size: {human_size(file_size)}\n"
        f"💾 `{filepath}`",
    )
    _cleanup_session(chat_id)


async def _handle_mobile_done(query, context, chat_id, title, filepath, icon, audio_only, send_as_doc):
    await _safe_edit(query, "📤 *Sending to Telegram…*")
    try:
        if audio_only:
            await send_audio(context, chat_id, filepath, title, icon)
        elif send_as_doc:
            await send_document(context, chat_id, filepath, title, icon)
        else:
            await send_video(context, chat_id, filepath, title, icon)
        await _safe_edit(query, "✅ *Sent to Telegram!* 💾 Save from your chat above.")
    finally:
        if os.path.exists(filepath):
            try:
                os.remove(filepath)
            except OSError as e:
                logger.debug(f"Failed to clean temp file {filepath}: {e}")
    _cleanup_session(chat_id)


async def _handle_both_done(query, context, chat_id, title, filepath, icon):
    await _safe_edit(query,
        f"✅ *Downloaded! Now sending to Telegram…*\n\n💾 Saved: `{filepath}`",
    )
    try:
        await send_video(context, chat_id, filepath, title, icon)
        await _safe_edit(query,
            f"✅ *All done!*\n\n💻 `{filepath}`\n📱 Sent to Telegram above.",
        )
    except Exception as e:
        logger.error(f"Telegram send failed for both-mode: {e}")
        await _safe_edit(query,
            f"⚠️ *Saved to laptop but Telegram send failed.*\n💾 `{filepath}`\n`{str(e)[:150]}`",
        )
    finally:
        _cleanup_session(chat_id)


async def _show_download_error(query, chat_id, platform, exc):
    err = str(exc).lower()
    full = str(exc)

    # ── Platform‑specific cookie guidance ───────────────
    platform_cookie_advice = {
        "Instagram":   ("Instagram",    "🔐 Instagram needs cookies. Use `/cookies` to set them up."),
        "Twitter/X":   ("Twitter/X",   "🐦 Twitter/X needs cookies. Use `/cookies` to set them up."),
        "Facebook":    ("Facebook",    "🌐 Facebook needs cookies. Use `/cookies`."),
        "LinkedIn":    ("LinkedIn",    "💼 LinkedIn needs cookies. Use `/cookies`."),
        "Threads":     ("Threads",     "🧵 Threads may need cookies. Use `/cookies`."),
        "TikTok":      ("TikTok",      "🎵 TikTok may need cookies. Use `/cookies` to avoid rate limits."),
    }

    if platform in platform_cookie_advice:
        map_key, cookie_msg = platform_cookie_advice[platform]
        cf = get_cookie_file(map_key)
        if not cf:
            msg = cookie_msg
        else:
            msg = f"{cookie_msg.split('.')[0]} failed. Cookies may be expired.\n`{full[:150]}`"
        await _safe_edit(query, f"❌ *Download Failed* ({platform})\n\n{msg}")
        _cleanup_session(chat_id)
        return

    # ── General error classification ────────────────────
    if "sign in" in err or "login" in err or "log in" in err:
        msg = f"🔒 Login required — this content may be private or age‑restricted.\n`{full[:150]}`"
    elif "private" in err:
        msg = "🔐 This video is private. Try exporting cookies from a logged‑in browser."
    elif "unavailable" in err or "removed" in err or "404" in err:
        msg = "🚫 This video is unavailable or has been removed."
    elif "copyright" in err or "takedown" in err or "blocked" in err:
        msg = "⚖️ Blocked due to copyright or takedown request."
    elif "rate" in err or "too many" in err or "429" in err:
        msg = "⏳ Rate limited. Wait a moment and try again."
    elif "geo" in err or "not available in your country" in err or "region" in err:
        msg = "🌍 This video is geo‑restricted and not available in your region."
    elif "age" in err or "18+" in err or "age-restrict" in err:
        msg = "🔞 Age‑restricted content. Log in and export cookies to download."
    elif "live" in err or "stream" in err:
        msg = "🔴 This is a live stream or premiere — wait until it ends to download."
    elif "membership" in err or "sponsor" in err or "member" in err:
        msg = "⭐ This video requires a channel membership. Log in to access."
    elif "download" in err and "limit" in err:
        msg = "⚠️ Download limit reached for this platform. Try again later."
    elif "timeout" in err or "timed out" in err:
        msg = f"⏱️ Connection timed out. The server may be slow or blocked.\n`{full[:150]}`"
    elif "drm" in err or "encrypt" in err:
        msg = "🔒 This video is DRM‑protected and cannot be downloaded."
    elif "premium" in err or "pro" in err:
        msg = "⭐ This content requires a premium subscription."
    elif "no video" in err or "no format" in err or "no matching" in err:
        msg = f"❓ No downloadable formats found for this platform.\n`{full[:150]}`"
    else:
        msg = f"`{full[:250]}`"

    await _safe_edit(query, f"❌ *Download Failed* ({platform})\n\n{msg}")
    _cleanup_session(chat_id)


# ═══════════════════════════════════════════════════════
#  PLAYLIST HANDLING
# ═══════════════════════════════════════════════════════

async def _handle_playlist(query, chat_id, data, context):
    sess = sessions.get(chat_id)
    if not sess or not sess.get("playlist_entries"):
        await _safe_edit(query, "⚠️ No playlist data.")
        return

    entries = sess["playlist_entries"]
    platform = sess["platform"]
    icon = sess["icon"]

    # Determine quality
    if data == "pl_audio":
        audio_only = True
        video_quality = "best"
    elif data == "pl_720p":
        audio_only = False
        video_quality = "720p"
    else:  # pl_best
        audio_only = False
        video_quality = "best"

    # ── Ask destination ─────────────────────────────────
    sess["format"] = "audio" if audio_only else "video"
    sess["video_quality"] = video_quality
    sess["audio_quality"] = "best"
    sess["playlist_mode"] = True

    total = len(entries)
    await _safe_edit(query,
        f"📋 *Playlist: {shorten(sess['title'], 50)}*\n"
        f"{total} videos\n\n"
        f"Where to save?",
        reply_markup=destination_picker(video=not audio_only, audio=audio_only),
    )


# ═══════════════════════════════════════════════════════
#  QUEUE PROCESSING  (iterative, not recursive)
# ═══════════════════════════════════════════════════════

async def _process_queue(chat_id, query=None, context=None):
    """Process queued URLs one at a time using a loop (no recursion)."""
    while True:
        async with _state_lock:
            if chat_id in active_downloads:
                return  # still busy

        next_url = user_config.pop_queue(chat_id)
        if not next_url:
            return  # queue empty

        async with _state_lock:
            active_downloads.add(chat_id)

        platform, icon = get_platform(next_url)

        try:
            info = await asyncio.to_thread(fetch_info, next_url, platform)
        except Exception as e:
            logger.error(f"Queued URL fetch failed [{next_url[:60]}]: {e}")
            if query:
                await _safe_edit(query, f"❌ Queued URL failed: `{next_url[:60]}…`")
            async with _state_lock:
                active_downloads.discard(chat_id)
            continue  # try next in queue instead of recursing

        title = clean_md(info.get("title", "Unknown"))
        async with _state_lock:
            sessions[chat_id] = {
                "url": next_url,
                "title": title,
                "platform": platform,
                "icon": icon,
                "format": "video",
                "video_quality": "best",
                "destination": "laptop",
            }

        if query:
            await _safe_edit(query,
                f"⏭️ *Queue: Next download starting…*\n📌 {shorten(title, 50)}",
            )
        await _run_download(chat_id, query, context)
        # After _run_download finishes, loop back to check for more


# ═══════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════

async def _safe_edit(query, text, reply_markup=None):
    """Edit message safely (handles deleted / expired / media captions)."""
    try:
        if query.message and (query.message.photo or query.message.video or query.message.document or query.message.audio or query.message.animation):
            await query.edit_message_caption(caption=text, parse_mode="Markdown", reply_markup=reply_markup)
        else:
            await query.edit_message_text(text, parse_mode="Markdown", reply_markup=reply_markup)
    except Exception as e:
        logger.debug(f"safe_edit failed: {e}")


async def _show_format_picker(query, chat_id):
    s = sessions.get(chat_id)
    if not s:
        return
    title = shorten(s["title"], 50)
    await _safe_edit(
        query,
        f"📌 *{title}*\n\nChoose format:",
        reply_markup=format_picker(),
    )


def _is_safe_thumbnail_url(url: str) -> bool:
    """Guard against SSRF: only allow http/https URLs to public IPs."""
    try:
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https"):
            return False
        hostname = parsed.hostname
        if not hostname:
            return False
        # Block obvious private/loopback ranges
        try:
            ip = ipaddress.ip_address(hostname)
            if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved:
                logger.warning(f"Blocked thumbnail URL to private IP: {hostname}")
                return False
        except ValueError:
            # hostname is a domain name, not IP — allow
            pass
        return True
    except Exception:
        return False


def _download_thumbnail_sync(chat_id: int, url: str) -> str | None:
    """Download a thumbnail image to cache (called via asyncio.to_thread)."""
    import urllib.request
    ext = url.split(".")[-1].split("?")[0]
    if ext not in ("jpg", "jpeg", "png", "webp"):
        ext = "jpg"
    path = os.path.join(config.THUMB_CACHE, f"thumb_{chat_id}_{int(time.time())}.{ext}")
    try:
        urllib.request.urlretrieve(url, path)
        return path
    except Exception:
        return None


def _cleanup_session(chat_id):
    """Remove session and its temp thumbnail."""
    sess = sessions.pop(chat_id, None)
    if sess:
        thumb = sess.get("thumb_path")
        if thumb and os.path.exists(thumb):
            try:
                os.remove(thumb)
            except OSError:
                pass
