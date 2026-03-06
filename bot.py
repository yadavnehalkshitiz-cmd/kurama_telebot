import os
import logging
import re
import asyncio
from datetime import datetime
from dotenv import load_dotenv
from telegram import Update
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler, MessageHandler, filters
import yt_dlp

# Load environment variables
load_dotenv()

# --- CONFIGURATION ---
TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
BASE_DOWNLOAD_FOLDER = os.path.join(os.path.expanduser("~"), "Downloads", "TelegramBot_Videos")
BASE_DOWNLOAD_FOLDER = os.path.join(os.path.expanduser("~"), "Downloads", "TelegramBot_Videos")

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
             "I am your personal Video Downloader Assistant.\n"
             "📂 Videos will be saved to: `{BASE_DOWNLOAD_FOLDER}`\n\n"
             "🚀 **Supported Platforms:**\n"
             "• YouTube (Shorts & Videos)\n"
             "• Instagram (Reels & Posts)\n"
             "• TikTok\n"
             "• Facebook\n\n"
             "👇 *Just send me a link to start!*",
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
    save_folder = os.path.join(BASE_DOWNLOAD_FOLDER, platform)
    
    # Create directory if it doesn't exist
    if not os.path.exists(save_folder):
        os.makedirs(save_folder)

    # Initial status message
    status_msg = await context.bot.send_message(
        chat_id=chat_id, 
        text=f"🔎 **Analyzing link from {platform}...**",
        parse_mode='Markdown'
    )

    # yt-dlp configuration
    script_dir = os.path.dirname(os.path.abspath(__file__))
    ydl_opts = {
        'outtmpl': os.path.join(save_folder, '%(title)s [%(id)s].%(ext)s'),
        'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',  # Ensure MP4
        'noplaylist': True,
        'quiet': True,
        'no_warnings': True,
        'restrictfilenames': True, # ASCII-only filenames
        'ffmpeg_location': script_dir, # Use script's directory for ffmpeg
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

    try:
        # Update status to Downloading
        await context.bot.edit_message_text(
            chat_id=chat_id, 
            message_id=status_msg.message_id, 
            text=f"⬇️ **Downloading from {platform}...**\n_(This might take a moment)_",
            parse_mode='Markdown'
        )
        
        # Check if ffmpeg exists in script directory
        script_dir = os.path.dirname(os.path.abspath(__file__))
        ffmpeg_path = os.path.join(script_dir, "ffmpeg.exe")
        if not os.path.exists(ffmpeg_path):
             logging.warning(f"ffmpeg.exe not found in {script_dir}. Some downloads might fail or lack merging.")

        # Define download task for to_thread
        def run_download():
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                title = info.get('title', 'Unknown Title')
                return filename, title

        # Run download in a separate thread to avoid blocking the bot
        filename, video_title = await asyncio.to_thread(run_download)
            
        # Clean up filename for display
        display_path = os.path.abspath(filename)
        
        # Success message
        await context.bot.edit_message_text(
            chat_id=chat_id, 
            message_id=status_msg.message_id, 
            text=f"✅ **Download Complete!**\n\n"
                 f"📺 **Title:** {video_title}\n"
                 f"📂 **Saved to:** `{display_path}`", 
            parse_mode='Markdown'
        )
        
    except Exception as e:
        logging.error(f"Download error: {e}")
        error_text = str(e)
        if "sign in" in error_text.lower():
            nice_error = "This video requires a login (it might be private or age-restricted)."
        else:
            nice_error = f"Could not download the video. Error details: {str(e)}"
            
        await context.bot.edit_message_text(
            chat_id=chat_id, 
            message_id=status_msg.message_id, 
            text=f"❌ **Failed to download**\n\n{nice_error}"
        )

if __name__ == '__main__':
    application = ApplicationBuilder().token(TOKEN).build()
    
    start_handler = CommandHandler('start', start)
    message_handler = MessageHandler(filters.TEXT & (~filters.COMMAND), handle_message)
    
    application.add_handler(start_handler)
    application.add_handler(message_handler)
    
    print(f"Bot is running! Saving files to: {BASE_DOWNLOAD_FOLDER}")
    application.run_polling()
