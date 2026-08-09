# 🦊 KuramaBot — Telegram Video Downloader

A smart Telegram bot that downloads videos from 12+ platforms directly to your **laptop** or **mobile**, with high-quality downloads and a real-time progress bar.

---

## 🧰 Tech Stack & Languages

Dart and Python are the primary languages in KuramaBot. Kotlin and Swift are
used only for native mobile integration, while JVM 17 is the Android build
target rather than an application language.

| Area | Stack |
|------|-------|
| Mobile app | Flutter, Dart |
| Backend and bot | Python, FastAPI, python-telegram-bot, yt-dlp, Uvicorn |
| Android | Android 9+ (API 28), Kotlin, Gradle 9.1, AGP 9.0.1, JVM 17 |
| iOS | Swift |
| Delivery | Docker, GitHub Actions, Render |

---

## ✨ Features

- 🎯 **Choose your destination** — Laptop, Mobile, or Both
- ⬇️ **High-quality downloads** — best available resolution (1080p/4K)
- 📊 **Live progress bar** — real-time download speed & ETA
- 📱 **Smart mobile sending** — auto-compresses if over Telegram's 50MB limit
- 🔐 **Cookie support** — fixes Instagram, Twitter/X, Facebook auth issues
- 🧠 **Platform-aware** — custom headers/extractors per platform
- 🔁 **Auto-restart** — supervisor keeps the bot alive 24/7

---

## 🌐 Supported Platforms

| Platform     | Notes                              |
|--------------|------------------------------------|
| YouTube      | Shorts, Videos, Playlists          |
| Instagram    | Reels, Posts (🍪 cookies required) |
| TikTok       | Videos, without watermark          |
| Facebook     | Videos (🍪 cookies recommended)    |
| Twitter/X    | Videos (🍪 cookies recommended)    |
| Reddit       | Video posts                        |
| Pinterest    | Video pins                         |
| Threads      | Video posts                        |
| Vimeo        | Videos                             |
| Dailymotion  | Videos                             |
| Twitch       | Clips & VODs                       |
| LinkedIn     | Videos                             |

---

## 📥 Download Flow

```
1. Paste a link
2. Bot fetches video info (title, duration, size, views)
3. Bot asks: "Where to download?"
   ┌─────────────────────────────────────────┐
   │  💻 Laptop   │  📱 Mobile  │  💻+📱 Both │
   └─────────────────────────────────────────┘
4. Downloads with live progress bar
5. Saves to ~/Downloads/KuramaBot/<Platform>/ (laptop)
   OR sends via Telegram (mobile) — auto-compressed if >50MB
```

---

## 🚀 Setup

### 1. Clone & install dependencies

```bash
cd telebot
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Configure your bot token

Edit `.env`:
```
TELEGRAM_BOT_TOKEN=your_token_here
```

### 3. (Optional) Configure a proxy

If you're behind a corporate firewall, in a restricted region, or want to route
video downloads through a specific network, set one of these environment
variables. The bot and `yt-dlp` will automatically use it.

**Priority:** `HTTPS_PROXY` → `HTTP_PROXY` → `ALL_PROXY`

**Option A — Add to your `.env` file:**
```
HTTPS_PROXY=http://127.0.0.1:1080
HTTP_PROXY=http://127.0.0.1:1080
```

**Option B — Set globally (Windows):**
```cmd
set HTTPS_PROXY=http://127.0.0.1:1080
python run_bot.py
```

**Option C — Set globally (Linux/macOS):**
```bash
export HTTPS_PROXY=http://127.0.0.1:1080
python run_bot.py
```

**Supported proxy schemes:**
| Scheme | Example                          |
|--------|----------------------------------|
| HTTP   | `http://proxy:8080`              |
| HTTPS  | `https://proxy:443`              |
| SOCKS5 | `socks5://127.0.0.1:1080`        |
| Auth   | `http://user:pass@proxy:8080`    |

> 💡 **Tip:** To verify your proxy is working, start the bot and check the logs.
> Download requests will be routed through the proxy automatically — no
> additional config needed.

### 4. Run the bot

```
run.bat
```
or
```
python run_bot.py
```

---

## 🍪 Fixing Instagram / Twitter Downloads

Instagram and Twitter/X require login cookies. If you see a cookie error:

1. Install Chrome extension: **Get cookies.txt LOCALLY**
2. Log in to instagram.com / twitter.com
3. Click the extension → Export
4. Save to `cookies/instagram.txt` or `cookies/twitter.txt`
5. Restart the bot — use `/cookies` in Telegram to verify

See `cookies/README.md` for detailed instructions.

---

## 📁 Folder Structure

```
telebot/
├── bot.py              # Main bot logic
├── run_bot.py          # Supervisor (auto-restart + health server)
├── run.bat             # Launch script for Windows
├── .env                # Bot token (not committed)
├── ffmpeg.exe          # FFmpeg for Windows
├── cookies/            # Place platform cookie files here
│   ├── README.md       # Cookie setup guide
│   ├── instagram.txt   # (not committed)
│   └── youtube.txt     # (not committed)
├── temp_mobile/        # Temp files for mobile-only downloads (auto-deleted)
└── requirements.txt
```

---

## 🤖 Bot Commands

| Command    | Description                          |
|------------|--------------------------------------|
| `/start`   | Welcome message                      |
| `/help`    | How to use the bot                   |
| `/cookies` | Check cookie status & setup guide    |
| `/cancel`  | Cancel current operation             |

---

## 📦 Requirements

- Python 3.10+
- FFmpeg (included as `ffmpeg.exe` on Windows)
- Telegram Bot Token (from [@BotFather](https://t.me/BotFather))
