# 🚀 KuramaBot — Deployment Checklist

KuramaBot runs **two processes** under one supervisor (`run_bot.py`):

1. **Telegram bot** (`bot.py`) — long-polling PTB bot.
2. **FastAPI server** (`api_server.py`) — powers the Flutter mobile app.

The supervisor restarts either process 5 seconds after it crashes. If the API
server exits immediately (e.g. `KURAMA_API_KEY` not set), the bot keeps running
but the **mobile app is down** — check the logs for the exit reason.

---

## 1. Required environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `TELEGRAM_BOT_TOKEN` | ✅ | — | BotFather token for the Telegram bot |
| `KURAMA_API_KEY` | ✅ | — | Bearer key for the API. **Server refuses to start** if missing or still `changeme-in-production` |
| `KURAMA_ADMIN_KEY` | ⬜ | *(uses API key)* | Separate key for `/api/admin/*` endpoints. When set, the main key no longer works on admin routes |

Generate a strong API key:

```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

## 2. Optional environment variables

| Variable | Default | Purpose |
|---|---|---|
| `PORT` / `API_PORT` | `8000` | HTTP port. **Render sets `PORT` automatically** — do not hard-code it |
| `API_HOST` | `0.0.0.0` | Bind address |
| `MAX_CONCURRENT_DOWNLOADS` | `5` | Max simultaneous yt-dlp downloads (see §5) |
| `PLAYLIST_MAX_ENTRIES` | `60` | Max videos bundled per playlist ZIP download (see §6.1) |
| `TASK_TTL` | `3600` | Seconds before completed/failed tasks + files are auto-purged (see §6) |
| `USER_CONFIGS_FILE` | `./user_configs.json` | Credits/subscriptions/payments persistence (see §7 — **important on Render**) |
| `INITIAL_FREE_CREDITS` | `3` | Free credits for new users |
| `MONTHLY_SUB_PRICE_NPR` | `500` | Premium price in NPR |
| `ADMIN_CHAT_ID` | `0` | Telegram admin chat for `/grantpremium`, payment approvals (`0` = disabled) |
| `CORS_ALLOWED_ORIGINS` | localhost only | Comma-separated origins (mobile app ignores CORS) |
| `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` | — | Route bot + yt-dlp through a proxy |
| `YTDLP_INSECURE` | off | `1` disables TLS verification — **only** for corporate MITM proxies |
| `ESEWA_ID`, `KHALTI_ID`, `BANK_DETAILS` | placeholders | Payment details shown in the app/QR |
| `TWITTER_BEARER_TOKEN`, `INSTAGRAM_APP_ID`, `TWITCH_CLIENT_ID` | public defaults | Platform API tokens (usually leave default) |

> ⚠️ `API_PORT` is only used when `PORT` is unset. On Render always rely on the
> injected `PORT`.

---

## 3. Deploy to Render.com

**Option A — Docker runtime** (uses the checked-in `Dockerfile`):

1. New **Web Service** → connect the repo.
2. **Runtime: Docker** (the Dockerfile installs Python 3.11 + ffmpeg and runs `run_bot.py`).
3. Set env vars (§1, §2).
4. **Health Check Path:** `/api/health` (public, no auth).
5. Deploy. First boot may take 1–2 min; free-tier cold starts take 30–60 s.

**Option B — Python runtime:**

- **Build command:** `pip install -r requirements.txt`
- **Start command:** `python run_bot.py`

**Minimal `render.yaml` blueprint:**

```yaml
services:
  - type: web
    name: kurama-bot
    runtime: docker
    plan: free            # see §7 about persistent disk on paid plans
    healthCheckPath: /api/health
    envVars:
      - key: KURAMA_API_KEY
        sync: false       # set manually / from secret
      - key: TELEGRAM_BOT_TOKEN
        sync: false
```

---

## 4. Deploy with Docker (self-hosted / VPS)

1. Create `.env` in the repo root with §1 + §2 values.
2. `docker compose up -d` — starts the container, maps host port **7860**, uses
   Google DNS to dodge Windows/VPN Docker DNS issues.
3. Make sure your firewall opens 7860 and the URL points there (the mobile app
   default is `https://kurama-telebot.onrender.com` — change it in app ⚙️).

```bash
docker compose up -d --build
docker compose logs -f          # watch both processes start
```

---

## 5. `MAX_CONCURRENT_DOWNLOADS`

Guards against unbounded yt-dlp threads (the classic free-tier OOM / crash loop).

| Instance | Recommended |
|---|---|
| Render free / 512 MB RAM | `2`–`3` |
| Render starter / 1 GB | `5` (default) |
| 2 GB+ / VPS | `8`–`10` |

- Exceeding the cap returns **HTTP 429** *before* charging a credit — the app
  shows a friendly "server busy" message.
- The cap counts `pending` + `downloading` tasks and is enforced atomically.
- Monitor live usage: `GET /api/admin/tasks` → `active` / `max_concurrent`.

## 6. `TASK_TTL` (task + file cleanup)

- Completed/failed tasks are purged **when a new download starts** (lazy sweep).
- `TASK_TTL` is the age threshold in seconds — default `3600` (1 hour).
- Purging deletes the task record **and its temp folder** under `temp_mobile/mobile_api/`.
- Stuck downloads (pending/downloading older than `TASK_TTL`) are **not**
  auto-purged by the sweep — remove them via the admin endpoint:

```bash
curl -X POST -H "Authorization: Bearer $KURAMA_ADMIN_KEY" \
     -d '{"older_than_seconds": 300, "stuck_after_seconds": 1800}' \
     https://your-host/api/admin/tasks/purge
```

- High-traffic instances: lower `TASK_TTL` (e.g. `1800`).

## 6.1 Playlist downloads (`PLAYLIST_MAX_ENTRIES`)

- The mobile app's info screen shows a **"Download all videos"** toggle for
  playlists. The server downloads every entry (flat-extraction, per-video
  progress) and bundles them into a **ZIP** file.
- `PLAYLIST_MAX_ENTRIES` caps the number of videos bundled per playlist —
  default `60`. Lower it (e.g. `30`) on small instances; each entry is a full
  yt-dlp download, so a huge playlist can be heavy.
- Playlist downloads count as **one** concurrency slot (`MAX_CONCURRENT_DOWNLOADS`).
- The app treats the resulting `.zip` as a document — save it from the
  Downloads tab, don't try to play it in-app.

## 6.2 Task persistence & retry

- The task store is **disk-backed** (`temp_mobile/mobile_api/tasks.json`, atomic
  writes) — completed/failed downloads survive restarts.
- On startup, tasks that were **in-flight when the server died** are marked
  `failed` and their spent credit is **refunded** automatically, so retrying
  never charges the user twice.
- **Retry a failed download** (app buttons in Downloads + the progress screen,
  or curl):

```bash
curl -X POST -H "Authorization: Bearer $KURAMA_API_KEY" \
     https://your-host/api/download/<task_id>/retry
# → {"status":"retried","task_id":"..."}
# 409 = not failed yet · 404 = unknown · 402 = no credits · 429 = busy
```

- Retry reuses the original format/quality, clears stale output, charges one
  credit, and spawns a fresh background thread.

## 6.3 Realtime progress (SSE)

- `GET /api/download/{task_id}/stream` streams task status over
  **Server-Sent Events** (one `event: status` frame per change, terminal frame
  when done, hard 15-min cap).
- The mobile app uses the stream automatically and **falls back to 3-second
  polling** if streaming is unavailable.

```bash
curl -N -H "Authorization: Bearer $KURAMA_API_KEY" \
     https://your-host/api/download/<task_id>/stream
# → event: status
data: {"status":"downloading","progress":42,...}
```

## 6.4 Keep-alive pinger (avoid free-tier cold starts)

Render **free** instances spin down after **~15 minutes of inactivity**; the
next request then pays a 30–60 s cold start (the app shows
`Server Offline / Waking up cloud server...`). A keep-alive monitor that hits
`/api/health` every few minutes keeps the instance warm. The endpoint is
**public and auth-free** (returns `{"status":"ok",...}`), so no server-side
configuration or key is needed — just point a pinger at it.

**UptimeRobot (free tier):**

1. Create a free account at [uptimerobot.com](https://uptimerobot.com).
2. **Add New Monitor** → Type **HTTP(s)** → URL `https://your-host/api/health`.
3. Set **Interval: 5 minutes** (the free-tier minimum — well inside Render's
   15-min spin-down window, so the instance never goes cold).
4. Switch the monitor type to **Keyword**, *Exists* → keyword `ok` — this
   catches both full downtime and a degraded (non-200 / non-`"ok"`) response.
5. Attach an alert contact (email) and save.

```yaml
# Monitor summary
url:      https://your-host/api/health
interval: 5 minutes
timeout:  30 s
keyword:  exists → "ok"
```

- The free tier covers this (50 monitors, 5-min interval); nothing runs on
  your server side — `/api/health` is deliberately public.
- **Alternatives** with equivalent free pings: **Better Stack**, **Cronitor**,
  or Render's built-in **Cron Job** (paid plans). Any periodic HTTP GET to
  `/api/health` works.
- Keep-alive pings only prevent *spin-down* — they don't replace the Render
  **Health Check Path** (`/api/health`), which kills and restarts unhealthy
  instances. Configure **both**.

## 7. Storage (don't lose user data!)

- **`user_configs.json`** holds credits, subscriptions, and payments.
- **`cookies/`** holds platform login cookies.
- **`temp_mobile/`** holds in-flight downloads + the task store
  (`mobile_api/tasks.json`). Files are safe to lose, but **the task records are
  not**: a restart marks interrupted downloads `failed` (credit refunded) so
  the app can **Retry** them instead of starting over from scratch.

On **Render free**, the filesystem is **ephemeral** — everything resets on every
redeploy, including credits and subscriptions. For a real deployment:

1. Use a **paid plan** with a **Persistent Disk**.
2. Point `USER_CONFIGS_FILE` at the disk, e.g. `/mnt/data/user_configs.json`.
3. Optionally copy `cookies/` to the disk and symlink it.

---

## 8. Health checks & verification

```bash
# 1. Liveness + config state (public)
curl https://your-host/api/health
# → {"status":"ok","api_key_configured":true,"active_downloads":0,
#    "uptime_seconds":123,"version":"1.1.1"}

# 2. Auth works (expect 200)
curl -H "Authorization: Bearer $KURAMA_API_KEY" https://your-host/api/platforms

# 3. Fetch info (expect JSON)
curl -H "Authorization: Bearer $KURAMA_API_KEY" \
     -d '{"url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ"}' \
     https://your-host/api/fetch-info

# 4. Admin task list
curl -H "Authorization: Bearer $KURAMA_ADMIN_KEY" https://your-host/api/admin/tasks

# 5. Full test suite
python -m unittest discover -s tests -v     # expect: 46 tests OK

# 6. Retry a failed download
curl -X POST -H "Authorization: Bearer $KURAMA_API_KEY" \
     https://your-host/api/download/<task_id>/retry

# 7. Download a full playlist (bundled as ZIP)
curl -X POST -H "Authorization: Bearer $KURAMA_API_KEY" \
     -d '{"url":"https://youtube.com/playlist?list=...","user_id":1,"playlist":true}' \
     https://your-host/api/download

# 8. Live status stream (SSE)
curl -N -H "Authorization: Bearer $KURAMA_API_KEY" \
     https://your-host/api/download/<task_id>/stream
```

**Mobile app:** open ⚙️ → server URL + **exactly the same** `KURAMA_API_KEY` →
Connect. The status dot turns green only when the key is also valid.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| API server exits instantly, bot fine | `KURAMA_API_KEY` missing/default | Set it (server refuses to start without it by design) |
| App: green dot but `Invalid API key` on fetch | Key mismatch app ↔ server | Paste the server's exact key in app ⚙️ |
| App: `Server Offline / Waking up cloud server...` | Free-tier cold start (30–60 s) | Tap **Retry** on the banner; or set up a keep-alive pinger (§6.4) / move to a paid plan |
| `429 Server is busy...` | Concurrency cap reached | Raise `MAX_CONCURRENT_DOWNLOADS` on a bigger instance |
| OOM / crash loop | Too many concurrent yt-dlp | Lower `MAX_CONCURRENT_DOWNLOADS`; check `/api/admin/tasks` for stuck tasks and purge |
| Disk full | Old task files | Lower `TASK_TTL`, run `/api/admin/tasks/purge` |
| Credits/subscriptions reset after redeploy | Ephemeral disk | Paid plan + persistent disk + `USER_CONFIGS_FILE` on it |
| Downloads show `failed` after a server restart | In-flight threads died with the process | Tap **Retry** — the interrupted attempt was refunded, retry re-runs it |
| Bot works, mobile app dead | `api_server.py` crashed | Read supervisor logs for the exit reason |

---

## 10. Post-deploy checklist

- [ ] `KURAMA_API_KEY` set (server started, `/api/health` → `api_key_configured: true`)
- [ ] `TELEGRAM_BOT_TOKEN` set, bot answers `/start`
- [ ] `KURAMA_ADMIN_KEY` set if you want admin-only task control
- [ ] `PORT` left to the platform; `7860` exposed for Docker self-hosting
- [ ] `MAX_CONCURRENT_DOWNLOADS` sized to the instance
- [ ] `PLAYLIST_MAX_ENTRIES` sized (default 60)
- [ ] `TASK_TTL` set; purge endpoint reachable
- [ ] Retry (`/api/download/<id>/retry`) and SSE (`/stream`) reachable
- [ ] Persistent disk configured + `USER_CONFIGS_FILE` pointing at it (non-free)
- [ ] Health check path `/api/health` wired in Render
- [ ] Keep-alive pinger configured (UptimeRobot → `/api/health`, 5-min interval) if on free tier — §6.4
- [ ] Mobile app connects (green dot) and a test download completes
- [ ] `python -m unittest discover -s tests -v` → **46 OK**
