"""KuramaBot — yt‑dlp download orchestration"""

import os
import logging
import asyncio

import yt_dlp

from config import (
    CHROME_UA,
    MOBILE_UA,
    COOKIES_FOLDER,
    PLATFORM_COOKIE_MAP,
    VIDEO_QUALITIES,
    MOBILE_QUALITIES,
    AUDIO_QUALITIES,
    AUDIO_BITRATES,
    YTDLP_PROXY,
    YTDLP_INSECURE,
    SOCKET_TIMEOUT,
    EXTRACT_TIMEOUT,
    TWITTER_BEARER_TOKEN,
    INSTAGRAM_APP_ID,
    TWITCH_CLIENT_ID,
)
from utils import get_ffmpeg_path

logger = logging.getLogger(__name__)


# ─── Cookie helper ──────────────────────────────────────

def get_cookie_file(platform: str) -> str | None:
    name_map = PLATFORM_COOKIE_MAP
    key = name_map.get(platform)
    if key:
        path = os.path.join(COOKIES_FOLDER, f"{key}.txt")
        if os.path.exists(path):
            return path
    generic = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cookies.txt")
    if os.path.exists(generic):
        return generic
    return None


# ─── Build yt‑dlp options ───────────────────────────────

def build_ydl_opts(
    save_folder: str,
    platform: str = "Other",
    progress_hook=None,
    for_mobile: bool = False,
    audio_only: bool = False,
    send_as_doc: bool = False,
    video_quality: str = "best",
    audio_quality: str = "best",
    playlist_mode: bool = False,
):
    """
    Build platform‑specific yt‑dlp options.

    Parameters:
        video_quality : 'best' | '1080p' | '720p' | '480p'
        audio_quality : 'best' | '320k'  | '192k'  | '128k'
    """
    ffmpeg_path = get_ffmpeg_path()
    cookie_file = get_cookie_file(platform)

    # ── Format string ───────────────────────────────────
    if audio_only:
        fmt = AUDIO_QUALITIES.get(audio_quality, AUDIO_QUALITIES["best"])
    elif for_mobile:
        fmt = MOBILE_QUALITIES.get(video_quality, MOBILE_QUALITIES["720p"])
    else:
        fmt = VIDEO_QUALITIES.get(video_quality, VIDEO_QUALITIES["best"])

    # ── Post‑processors ─────────────────────────────────
    postprocessors = []
    if audio_only:
        bitrate = AUDIO_BITRATES.get(audio_quality, "0")
        postprocessors.append({
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": bitrate,
        })
        postprocessors.extend([
            {"key": "FFmpegMetadata", "add_metadata": True},
            {"key": "EmbedThumbnail"},
        ])
    elif send_as_doc:
        # Document: keep best quality, no re-encoding
        pass
    else:
        postprocessors.append({
            "key": "FFmpegVideoConvertor",
            "preferedformat": "mp4",
        })

    # ── Base opts ───────────────────────────────────────
    opts = {
        "outtmpl": os.path.join(save_folder, "%(title)s [%(id)s].%(ext)s"),
        "format": fmt,
        "noplaylist": not playlist_mode,
        "quiet": True,
        "no_warnings": True,
        "restrictfilenames": True,
        "ffmpeg_location": ffmpeg_path,
        "geo_bypass": True,
        "user_agent": CHROME_UA,
        "socket_timeout": SOCKET_TIMEOUT,
        "extractor_args": {},  # will be overridden per-platform
        "retries": 5,
        "fragment_retries": 5,
        "file_access_retries": 3,
        "extractor_retries": 3,
        "extract_flat": False,
        "postprocessors": postprocessors,
    }

    if audio_only:
        # yt-dlp maps title/uploader into ID3 title/artist and converts the
        # downloaded thumbnail into MP3-compatible album artwork.
        opts["writethumbnail"] = True

    # Only disable TLS verification if explicitly opted in via env var
    if YTDLP_INSECURE:
        opts["nocheckcertificate"] = True
        logger.warning("TLS certificate verification is disabled (YTDLP_INSECURE=1)")

    if YTDLP_PROXY:
        opts["proxy"] = YTDLP_PROXY

    if not audio_only and not send_as_doc:
        opts["merge_output_format"] = "mp4"

    if cookie_file:
        opts["cookiefile"] = cookie_file

    if progress_hook:
        opts["progress_hooks"] = [progress_hook]

    # ── Platform overrides ──────────────────────────────
    _apply_platform_overrides(opts, platform, cookie_file, for_mobile)

    return opts


def _apply_platform_overrides(opts, platform, cookie_file, for_mobile):
    """Add platform‑specific headers / extractor args."""

    if platform == "YouTube":
        opts["extractor_args"] = {
            "youtube": {
                "player_client": ["web", "android", "ios"],
                "skip": ["hls", "dash"] if not for_mobile else [],
            }
        }

    elif platform == "Instagram":
        # Instagram serves single merged streams — NOT separate video+audio tracks.
        # Forcing bestvideo+bestaudio fails because those streams don't exist.
        # Override format to a single-stream selector regardless of quality choice.
        quality = opts.get("format", "best")
        # Map the quality selector to Instagram-compatible single-stream format
        _insta_fmt_map = {
            "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best":            "best[ext=mp4]/best",
            "bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/best[height<=1080]/best": "best[height<=1080][ext=mp4]/best[height<=1080]/best",
            "bestvideo[ext=mp4][height<=720]+bestaudio[ext=m4a]/best[height<=720]/best":  "best[height<=720][ext=mp4]/best[height<=720]/best",
            "bestvideo[ext=mp4][height<=480]+bestaudio[ext=m4a]/best[height<=480]/best":  "best[height<=480][ext=mp4]/best[height<=480]/best",
        }
        opts["format"] = _insta_fmt_map.get(quality, "best[ext=mp4]/best")
        opts["http_headers"] = {
            "User-Agent": CHROME_UA,
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept-Encoding": "gzip, deflate, br",
            "Referer": "https://www.instagram.com/",
            "X-IG-App-ID": INSTAGRAM_APP_ID,
            "X-ASBD-ID": "129477",
            "X-IG-WWW-Claim": "0",
            "Origin": "https://www.instagram.com",
        }
        opts["extractor_args"] = {"instagram": {"include_dash_manifest": ["0"]}}
        # Allow session cookies from browser as fallback
        if not cookie_file:
            logger.warning("Instagram download attempted without cookies — login-required posts will fail")
        else:
            logger.debug(f"Instagram: using cookie file {cookie_file}")

    elif platform == "TikTok":
        opts["user_agent"] = CHROME_UA
        opts["http_headers"] = {
            "User-Agent": CHROME_UA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Referer": "https://www.tiktok.com/",
        }

    elif platform == "Twitter/X":
        opts["http_headers"] = {
            "User-Agent": CHROME_UA,
            "Authorization": f"Bearer {TWITTER_BEARER_TOKEN}",
        }
        if not cookie_file:
            logger.warning("Twitter/X download attempted without cookies — may fail")

    elif platform == "Facebook":
        opts["http_headers"] = {
            "User-Agent": CHROME_UA,
            "Accept-Language": "en-US,en;q=0.5",
        }

    elif platform == "Reddit":
        opts["http_headers"] = {"User-Agent": "Mozilla/5.0 (compatible; KuramaBot/1.0)"}

    elif platform == "Pinterest":
        opts["user_agent"] = MOBILE_UA

    elif platform in ("Vimeo", "Dailymotion"):
        opts["http_headers"] = {
            "User-Agent": CHROME_UA,
            "Referer": f"https://www.{platform.lower()}.com/",
        }

    elif platform == "Threads":
        opts["user_agent"] = MOBILE_UA
        opts["http_headers"] = {
            "User-Agent": MOBILE_UA,
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "https://www.threads.net/",
            "Origin": "https://www.threads.net",
        }

    elif platform == "LinkedIn":
        opts["http_headers"] = {
            "User-Agent": CHROME_UA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Referer": "https://www.linkedin.com/",
            "X-Li-Lang": "en_US",
            "X-RestLi-Protocol-Version": "2.0.0",
        }
        if not cookie_file:
            logger.warning("LinkedIn download attempted without cookies — may fail")

    elif platform == "Twitch":
        opts["http_headers"] = {
            "User-Agent": CHROME_UA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Referer": "https://www.twitch.tv/",
            "Client-ID": TWITCH_CLIENT_ID,
        }
        opts["extractor_args"] = {
            "twitch": {
                "client_id": [TWITCH_CLIENT_ID],
            }
        }

    elif platform == "Bluesky":
        opts["http_headers"] = {
            "User-Agent": "Mozilla/5.0 (compatible; KuramaBot/1.0)",
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.5",
        }

    elif platform == "VK":
        opts["http_headers"] = {
            "User-Agent": CHROME_UA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "ru-RU,ru;q=0.9,en;q=0.5",
            "Referer": "https://vk.com/",
        }
        if not cookie_file:
            logger.warning("VK download attempted without cookies — may fail")

    elif platform == "Bilibili":
        opts["http_headers"] = {
            "User-Agent": MOBILE_UA,
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.5",
            "Referer": "https://www.bilibili.com/",
        }


# ─── Fetch info (no download) ───────────────────────────

def fetch_info(url: str, platform: str):
    """Fetch video/playlist info without downloading."""
    opts = build_ydl_opts(
        save_folder="",
        platform=platform,
        playlist_mode=True,  # detect playlists
    )
    opts["skip_download"] = True
    opts.pop("outtmpl", None)
    opts.pop("progress_hooks", None)
    opts.pop("postprocessors", None)
    # Extract full playlist info (not just first video)
    opts.pop("noplaylist", None)

    with yt_dlp.YoutubeDL(opts) as ydl:
        return ydl.extract_info(url, download=False)


# ─── Download a single video ────────────────────────────

def download_single(url: str, ydl_opts: dict):
    """Download a single video/audio. Returns (filepath, info_dict)."""
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=True)
        filename = ydl.prepare_filename(info)

        if not os.path.exists(filename):
            base = os.path.splitext(filename)[0]
            # Check video extensions
            for ext in (".mp4", ".mkv", ".webm", ".mov"):
                if os.path.exists(base + ext):
                    filename = base + ext
                    break
            else:
                # Check audio extensions
                for ext in (".mp3", ".m4a", ".aac", ".ogg", ".opus", ".wav"):
                    if os.path.exists(base + ext):
                        filename = base + ext
                        break
        return filename, info


# ─── Compress video for Telegram ────────────────────────

async def compress_for_telegram(input_path: str) -> str:
    """Compress video to fit under 50 MB using FFmpeg."""
    ffmpeg_path = get_ffmpeg_path()
    out_path = input_path.replace(".mp4", "_compressed.mp4")
    cmd = [
        ffmpeg_path,
        "-i", input_path,
        "-vcodec", "libx264",
        "-crf", "28",
        "-preset", "fast",
        "-vf", "scale=-2:720",
        "-acodec", "aac",
        "-b:a", "128k",
        "-movflags", "+faststart",
        "-y", out_path,
    ]
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await proc.communicate()
    if proc.returncode != 0:
        raise RuntimeError(stderr.decode()[-300:])
    return out_path
