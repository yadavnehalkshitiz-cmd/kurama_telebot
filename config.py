"""KuramaBot — Configuration"""

import os
import re
import sys
import logging
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

# ─── Telegram ──────────────────────────────────────────
TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_LIMIT = 50 * 1024 * 1024  # 50 MB

# ─── Folders ────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Laptop default save folder
LAPTOP_FOLDER = os.path.join(os.path.expanduser("~"), "Downloads", "KuramaBot")
os.makedirs(LAPTOP_FOLDER, exist_ok=True)

# Temp folder for Telegram-only downloads (cleaned up after send)
TEMP_FOLDER = os.path.join(BASE_DIR, "temp_mobile")
os.makedirs(TEMP_FOLDER, exist_ok=True)

# Cookie storage
COOKIES_FOLDER = os.path.join(BASE_DIR, "cookies")
os.makedirs(COOKIES_FOLDER, exist_ok=True)

# User config persistence
USER_CONFIGS_FILE = os.path.join(BASE_DIR, "user_configs.json")

# ─── Thumbnail cache ────────────────────────────────────
THUMB_CACHE = os.path.join(BASE_DIR, "thumb_cache")
os.makedirs(THUMB_CACHE, exist_ok=True)

# ─── User-Agents ────────────────────────────────────────
CHROME_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/139.0.0.0 Safari/537.36"
)
MOBILE_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) "
    "Version/17.0 Mobile/15E148 Safari/604.1"
)

# ─── Quality presets ────────────────────────────────────
VIDEO_QUALITIES = {
    "best":  "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
    "1080p": "bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/best[height<=1080]/best",
    "720p":  "bestvideo[ext=mp4][height<=720]+bestaudio[ext=m4a]/best[height<=720]/best",
    "480p":  "bestvideo[ext=mp4][height<=480]+bestaudio[ext=m4a]/best[height<=480]/best",
}

MOBILE_QUALITIES = {
    "720p":  "bestvideo[ext=mp4][height<=720]+bestaudio[ext=m4a]/best[height<=720]/best",
    "480p":  "bestvideo[ext=mp4][height<=480]+bestaudio[ext=m4a]/best[height<=480]/best",
}

AUDIO_QUALITIES = {
    "best":  "bestaudio/best",
    "320k":  "bestaudio[abr<=320]/bestaudio/best",
    "192k":  "bestaudio[abr<=192]/bestaudio/best",
    "128k":  "bestaudio[abr<=128]/bestaudio/best",
}

AUDIO_BITRATES = {
    "best": "0",
    "320k": "320",
    "192k": "192",
    "128k": "128",
}

# ─── Cookie map ─────────────────────────────────────────
PLATFORM_COOKIE_MAP = {
    "Instagram": "instagram",
    "YouTube": "youtube",
    "Twitter/X": "twitter",
    "Facebook": "facebook",
    "TikTok": "tiktok",
    "Reddit": "reddit",
    "Threads": "threads",
    "Bluesky": "bluesky",
    "VK": "vk",
}

# ─── Platform detection (regex‑based) ───────────────────
PLATFORM_RULES = [
    (re.compile(r"(?:^|[./])youtube\.com|youtu\.be"),         "YouTube",     "🎬"),
    (re.compile(r"(?:^|[./])instagram\.com"),                  "Instagram",   "📸"),
    (re.compile(r"(?:^|[./])tiktok\.com"),                     "TikTok",      "🎵"),
    (re.compile(r"(?:^|[./])facebook\.com|fb\.watch"),         "Facebook",    "🌐"),
    (re.compile(r"(?:^|[./])twitter\.com|(?:^|[./])x\.com"),    "Twitter/X",   "🐦"),
    (re.compile(r"(?:^|[./])reddit\.com|redd\.it"),            "Reddit",      "🤖"),
    (re.compile(r"(?:^|[./])pinterest\.com|pin\.it"),          "Pinterest",   "📌"),
    (re.compile(r"(?:^|[./])threads\.net"),                    "Threads",     "🧵"),
    (re.compile(r"(?:^|[./])linkedin\.com"),                   "LinkedIn",    "💼"),
    (re.compile(r"(?:^|[./])twitch\.tv"),                      "Twitch",      "🎮"),
    (re.compile(r"(?:^|[./])dailymotion\.com"),                "Dailymotion", "📺"),
    (re.compile(r"(?:^|[./])vimeo\.com"),                      "Vimeo",       "🎥"),
    (re.compile(r"(?:^|[./])bsky\.app"),                        "Bluesky",     "🦋"),
    (re.compile(r"(?:^|[./])vk\.(?:com|ru)"),                   "VK",          "💬"),
    (re.compile(r"(?:^|[./])bilibili\.com"),                    "Bilibili",    "📺"),
]

# ─── Connection / proxy ─────────────────────────────────
# Bot will respect http_proxy / https_proxy / all_proxy env vars
HTTP_PROXY = os.getenv("HTTP_PROXY") or os.getenv("http_proxy") or None
HTTPS_PROXY = os.getenv("HTTPS_PROXY") or os.getenv("https_proxy") or None
ALL_PROXY = os.getenv("ALL_PROXY") or os.getenv("all_proxy") or None

# yt‑dlp proxy (use https_proxy if set, fall back to http_proxy)
YTDLP_PROXY = HTTPS_PROXY or HTTP_PROXY or ALL_PROXY or None

# Retry config (exponential backoff)
RETRY_MAX_ATTEMPTS = 5
RETRY_BASE_DELAY = 2  # seconds, doubles each attempt
RETRY_MAX_DELAY = 60  # seconds

# ─── Mobile API ────────────────────────────────────────
_raw_api_key = os.getenv("KURAMA_API_KEY")
if not _raw_api_key or _raw_api_key == "changeme-in-production":
    API_AUTH_KEY = None  # Will cause API server to refuse startup
    logger.warning(
        "KURAMA_API_KEY is missing or still set to the default. "
        "The API server will refuse to start until a real key is set in .env"
    )
else:
    API_AUTH_KEY = _raw_api_key

# Default API binding (0.0.0.0 for cloud hosting, PORT env var from platform)
API_HOST = os.getenv("API_HOST") or "0.0.0.0"
API_PORT = int(os.getenv("PORT") or os.getenv("API_PORT") or "8000")

# CORS allowed origins (comma-separated in env, or default to localhost only)
_origins_raw = os.getenv("CORS_ALLOWED_ORIGINS", "")
ALLOWED_ORIGINS = [o.strip() for o in _origins_raw.split(",") if o.strip()] or [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
]

# Timeouts
SOCKET_TIMEOUT = 30
EXTRACT_TIMEOUT = 45

# ─── Input validation ──────────────────────────────────
MAX_URL_LENGTH = 2048

# ─── Task cleanup ──────────────────────────────────────
TASK_TTL = int(os.getenv("TASK_TTL", "3600"))  # seconds before completed tasks are purged

# ─── TLS verification ──────────────────────────────────
# Only disable if you're behind a corporate proxy with a custom CA cert.
# Set YTDLP_INSECURE=1 in .env to disable — NOT recommended.
YTDLP_INSECURE = os.getenv("YTDLP_INSECURE", "").lower() in ("1", "true", "yes")

# ─── Platform API tokens (env-overridable) ──────────────
# These are public client tokens scraped from web clients.
# They're not secret, but keeping them configurable means you can
# swap them when platforms rotate their keys without editing code.
TWITTER_BEARER_TOKEN = os.getenv(
    "TWITTER_BEARER_TOKEN",
    "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs"
    "%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA",
)
INSTAGRAM_APP_ID = os.getenv("INSTAGRAM_APP_ID", "936619743392459")
TWITCH_CLIENT_ID = os.getenv("TWITCH_CLIENT_ID", "kimne78kx3ncx6brgo4mv6wki5h1ko")
