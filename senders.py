"""KuramaBot — Telegram message senders"""

import os
import logging

from config import TELEGRAM_LIMIT
from utils import human_size
from downloader import compress_for_telegram

logger = logging.getLogger(__name__)

# Telegram upload timeouts (large files can take a while)
_READ_TIMEOUT = 120   # seconds
_WRITE_TIMEOUT = 120  # seconds


async def send_video(context, chat_id, filepath, title, icon):
    """Send video, compressing if over 50 MB."""
    file_size = os.path.getsize(filepath)
    compressed_path = None

    try:
        if file_size > TELEGRAM_LIMIT:
            await context.bot.send_message(
                chat_id=chat_id,
                text=(
                    f"📦 *File is {human_size(file_size)}, over Telegram's 50 MB limit.*\n"
                    f"🔧 Compressing to 720p…\n_(Hang tight!)_"
                ),
                parse_mode="Markdown",
            )
            compressed_path = await compress_for_telegram(filepath)
            c_size = os.path.getsize(compressed_path)

            if c_size > TELEGRAM_LIMIT:
                raise ValueError(
                    f"Even after compression the file is {human_size(c_size)}. "
                    "This video is too long/large for Telegram bots (50 MB limit)."
                )
            filepath = compressed_path

        with open(filepath, "rb") as f:
            await context.bot.send_video(
                chat_id=chat_id,
                video=f,
                caption=f"{icon} *{title}*\n\n_Sent via KuramaBot_",
                parse_mode="Markdown",
                supports_streaming=True,
                read_timeout=_READ_TIMEOUT,
                write_timeout=_WRITE_TIMEOUT,
            )
    finally:
        # Always clean up compressed file, even if send fails
        if compressed_path and os.path.exists(compressed_path):
            try:
                os.remove(compressed_path)
            except OSError as e:
                logger.debug(f"Failed to clean compressed file: {e}")


async def send_audio(context, chat_id, filepath, title, icon):
    """Send audio file (MP3)."""
    with open(filepath, "rb") as f:
        await context.bot.send_audio(
            chat_id=chat_id,
            audio=f,
            caption=f"{icon} *{title}*\n\n_Sent via KuramaBot_",
            parse_mode="Markdown",
            read_timeout=_READ_TIMEOUT,
            write_timeout=_WRITE_TIMEOUT,
        )


async def send_document(context, chat_id, filepath, title, icon):
    """Send as document (original quality, no re-encode)."""
    file_size = os.path.getsize(filepath)
    if file_size > TELEGRAM_LIMIT:
        raise ValueError(
            f"File is {human_size(file_size)} — over Telegram's 50 MB limit. "
            "Try Video format instead (it will compress)."
        )

    with open(filepath, "rb") as f:
        await context.bot.send_document(
            chat_id=chat_id,
            document=f,
            caption=f"{icon} *{title}*\n\n_Sent via KuramaBot_",
            parse_mode="Markdown",
            read_timeout=_READ_TIMEOUT,
            write_timeout=_WRITE_TIMEOUT,
        )
