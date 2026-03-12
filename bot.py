import os
import logging
import re
import asyncio
import shutil
from datetime import datetime
from dotenv import load_dotenv
from telegram import Update
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler, MessageHandler, filters
import yt_dlp

# Load environment variables
load_dotenv()

# --- CONFIGURATION ---
TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
# Use a local folder for temporary downloads
BASE_DOWNLOAD_FOLDER = "downloads"

# Configure logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user.first_name
    await context.bot.send_message(
        chat_id=update.effective_chat.id, 
        text=f"👋 **Hello {user}!**\n\n"
             "I am your personal Video Downloader Assistant.\n\n"
             "🚀 **Supported Platforms:**\n"
             "• YouTube (Shorts & Videos)\n"
             "• Instagram (Reels & Posts)\n"
             "• TikTok\n"
             "• Facebook\n\n"
             "👇 *Just send me a link and I'll send you the video!*",
        parse_mode='Markdown'
    )

def get_platform_name(url):
    domain = re.search(r'(?:https?://)?(?:www\.)?([^/]+)', url)
    if domain:
        name = domain.group(1).lower()
        if 'youtube' in name or 'youtu.be' in name: return 'YouTube'
        if 'instagram' in name: return 'Instagram'
        if 'tiktok' in name: return 'TikTok'
        if 'facebook' in name or 'fb.watch' in name: return 'Facebook'
        if 'twitter' in name or 'x.com' in name: return 'Twitter'
    return 'Other'

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    url = update.message.text.strip()
    chat_id = update.effective_chat.id
    
    # Basic URL validation
    if not url.startswith(('http://', 'https://')):
        await context.bot.send_message(chat_id=chat_id, text="⚠️ That doesn't look like a valid link. Please send a URL starting with http:// or https://")
        return

    platform = get_platform_name(url)
    # Use a safe folder name based on platform
    save_folder = os.path.join(BASE_DOWNLOAD_FOLDER, platform)
    
    # Create directory if it doesn't exist
    if not os.path.exists(save_folder):
        os.makedirs(save_folder, exist_ok=True)

    # Initial status message
    status_msg = await context.bot.send_message(
        chat_id=chat_id, 
        text=f"🔎 **Analyzing link from {platform}...**",
        parse_mode='Markdown'
    )

    # Detect ffmpeg path
    script_dir = os.path.dirname(os.path.abspath(__file__))
    ffmpeg_cmd = "ffmpeg" # Default for Linux/Docker/Path
    if os.name == 'nt': # Windows
        local_ffmpeg = os.path.join(script_dir, "ffmpeg.exe")
        if os.path.exists(local_ffmpeg):
            ffmpeg_cmd = local_ffmpeg

    # yt-dlp configuration
    ydl_opts = {
        'outtmpl': os.path.join(save_folder, '%(title)s [%(id)s].%(ext)s'),
        'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
        'noplaylist': True,
        'quiet': True,
        'no_warnings': True,
        'restrictfilenames': True,
        'ffmpeg_location': ffmpeg_cmd,
        'nocheckcertificate': True,
        'geo_bypass': True,
        'extractor_args': {
            'youtube': {
                'player_client': ['android', 'ios'],
                'skip': ['webpage']
            }
        },
        'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    }

    file_to_send = None
    try:
        # Update status to Downloading
        await context.bot.edit_message_text(
            chat_id=chat_id, 
            message_id=status_msg.message_id, 
            text=f"⬇️ **Downloading from {platform}...**\n_(This might take a moment)_",
            parse_mode='Markdown'
        )
        
        # Define download task
        def run_download():
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                # Ensure we handle merged files (extension might change)
                if not os.path.exists(filename):
                     # If the extension changed (e.g. .mkv to .mp4), find the file
                     base = os.path.splitext(filename)[0]
                     for ext in ['.mp4', '.mkv', '.webm']:
                         if os.path.exists(base + ext):
                             filename = base + ext
                             break
                return filename, info.get('title', 'Unknown Title')

        # Run download in a separate thread
        filename, video_title = await asyncio.to_thread(run_download)
        file_to_send = filename
            
        # Update status to Sending
        await context.bot.edit_message_text(
            chat_id=chat_id, 
            message_id=status_msg.message_id, 
            text=f"📤 **Download Complete! Sending video...**",
            parse_mode='Markdown'
        )

        # Send the video
        with open(filename, 'rb') as video_file:
            await context.bot.send_video(
                chat_id=chat_id,
                video=video_file,
                caption=f"✅ **{video_title}**\n\nDownloaded via @KuramaBot",
                parse_mode='Markdown'
            )
        
        # Delete status message
        await context.bot.delete_message(chat_id=chat_id, message_id=status_msg.message_id)
        
    except Exception as e:
        logging.error(f"Error: {e}")
        error_text = str(e)
        nice_error = f"Could not process the video. Error: {error_text[:100]}..."
        
        if "sign in" in error_text.lower():
            nice_error = "This video requires a login (it might be private or age-restricted)."
        elif "too large" in error_text.lower():
             nice_error = "The video is too large for Telegram (limit is 50MB for bots)."

        await context.bot.edit_message_text(
            chat_id=chat_id, 
            message_id=status_msg.message_id, 
            text=f"❌ **Failed**\n\n{nice_error}"
        )
    finally:
        # Cleanup: Delete the file after sending or error
        if file_to_send and os.path.exists(file_to_send):
            try:
                os.remove(file_to_send)
                logging.info(f"Cleaned up file: {file_to_send}")
            except Exception as e:
                logging.error(f"Cleanup error: {e}")

if __name__ == '__main__':
    # Ensure download folder exists
    os.makedirs(BASE_DOWNLOAD_FOLDER, exist_ok=True)
    
    application = ApplicationBuilder().token(TOKEN).build()
    
    start_handler = CommandHandler('start', start)
    message_handler = MessageHandler(filters.TEXT & (~filters.COMMAND), handle_message)
    
    application.add_handler(start_handler)
    application.add_handler(message_handler)
    
    print(f"Bot is running! Temporary storage in: {BASE_DOWNLOAD_FOLDER}")
    application.run_polling()
