import asyncio
import os
import sys
import yt_dlp

# Force UTF-8 output on Windows terminal
if sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

from downloader import build_ydl_opts
from utils import get_platform

async def run_tiktok_info():
    url = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
    platform, icon = get_platform(url)
    print(f"Testing {platform} {icon}...")
    
    opts = build_ydl_opts(
        save_folder="temp_mobile",
        platform=platform,
        for_mobile=False,
    )
    opts['skip_download'] = True
    opts.pop('outtmpl', None)
    
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            print("[*] Extracting info...")
            info = ydl.extract_info(url, download=False)
            print(f"✅ Success!")
            print(f"Title: {info.get('title')}")
            print(f"Duration: {info.get('duration')}s")
            return True
    except Exception as e:
        print(f"❌ Failed: {e}")
        return False

if __name__ == "__main__":
    asyncio.run(test_tiktok_info())
