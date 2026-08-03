"""KuramaBot — Inline keyboard builders"""

from telegram import InlineKeyboardButton, InlineKeyboardMarkup


def format_picker():
    """First screen: choose format type."""
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("🎬 Video", callback_data="fmt_video"),
            InlineKeyboardButton("🎵 Audio", callback_data="fmt_audio"),
            InlineKeyboardButton("📄 File (no re-encode)", callback_data="fmt_doc"),
        ],
        [InlineKeyboardButton("❌ Cancel", callback_data="cancel")],
    ])


def video_quality_picker():
    """Video quality selection."""
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("🎯 Best", callback_data="vq_best"),
            InlineKeyboardButton("1080p", callback_data="vq_1080p"),
        ],
        [
            InlineKeyboardButton("720p", callback_data="vq_720p"),
            InlineKeyboardButton("480p", callback_data="vq_480p"),
        ],
        [InlineKeyboardButton("◀️ Back", callback_data="back_to_format")],
    ])


def audio_quality_picker():
    """Audio bitrate selection."""
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("🎯 Best", callback_data="aq_best"),
            InlineKeyboardButton("320kbps", callback_data="aq_320k"),
        ],
        [
            InlineKeyboardButton("192kbps", callback_data="aq_192k"),
            InlineKeyboardButton("128kbps", callback_data="aq_128k"),
        ],
        [InlineKeyboardButton("◀️ Back", callback_data="back_to_format")],
    ])


def destination_picker(video: bool = True, audio: bool = False, doc: bool = False):
    """Choose where to send the download."""
    buttons = [[InlineKeyboardButton("💻 Laptop", callback_data="dest_laptop")]]

    if video or doc:
        buttons[0].append(InlineKeyboardButton("📱 Telegram", callback_data="dest_mobile"))
        buttons[0].append(InlineKeyboardButton("💻+📱 Both", callback_data="dest_both"))
    elif audio:
        buttons[0].append(InlineKeyboardButton("📱 Telegram", callback_data="dest_mobile"))

    buttons.append([InlineKeyboardButton("◀️ Back", callback_data="back_to_quality")])
    return InlineKeyboardMarkup(buttons)


def playlist_actions():
    """Playlist download options."""
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("📥 Download All (Best)", callback_data="pl_best"),
            InlineKeyboardButton("📥 Download All (720p)", callback_data="pl_720p"),
        ],
        [
            InlineKeyboardButton("🎵 Audio All", callback_data="pl_audio"),
        ],
        [InlineKeyboardButton("◀️ Cancel", callback_data="cancel")],
    ])


def setfolder_confirm():
    """Confirm folder creation."""
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("✅ Create it", callback_data="mkdir_yes"),
            InlineKeyboardButton("❌ No", callback_data="mkdir_no"),
        ],
    ])


def buy_subscription_keyboard():
    """Subscription purchase options."""
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("💳 Buy Subscription (500 NPR)", callback_data="buy_info"),
        ],
        [
            InlineKeyboardButton("📊 My Balance / Status", callback_data="check_credits"),
        ],
    ])


def admin_payment_approval_keyboard(user_id: int, tx_id: str):
    """Admin inline keyboard for payment verification."""
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("✅ Approve", callback_data=f"pay_approve_{user_id}_{tx_id}"),
            InlineKeyboardButton("❌ Reject", callback_data=f"pay_reject_{user_id}_{tx_id}"),
        ],
    ])

