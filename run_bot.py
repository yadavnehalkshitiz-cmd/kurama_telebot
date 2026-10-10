import subprocess
import time
import sys
import os
import signal

import threading
import urllib.request
from config import KEEP_ALIVE_URL, API_PORT


def start_keep_alive_pinger():
    """Periodically ping Render/server health endpoint to prevent free-tier spin down."""
    target_url = KEEP_ALIVE_URL
    if not target_url:
        target_url = "https://kurama-telebot.onrender.com"

    target_url = target_url.rstrip("/")
    probe_url = target_url if target_url.endswith(("/health", "/api/health")) else f"{target_url}/health"

    def _pinger_loop():
        print(f"[KEEPALIVE] Keep-alive active -> Pinging {probe_url} every 4 minutes to guarantee 24/7 uptime.")
        time.sleep(15)
        while True:
            # 1. External HTTPS ping (routes through Render external load balancer, resetting inactivity timer)
            try:
                req = urllib.request.Request(
                    probe_url,
                    headers={"User-Agent": "KuramaBot-KeepAlive/2.0"},
                )
                with urllib.request.urlopen(req, timeout=20) as resp:
                    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [KEEPALIVE] External ping to {probe_url} OK (HTTP {resp.getcode()})")
            except Exception as e:
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [KEEPALIVE] External ping notice: {e}")

            # 2. Local loopback ping to ensure internal FastAPI server is healthy
            try:
                local_url = f"http://127.0.0.1:{API_PORT}/health"
                req_local = urllib.request.Request(
                    local_url,
                    headers={"User-Agent": "KuramaBot-KeepAlive/2.0"},
                )
                with urllib.request.urlopen(req_local, timeout=5) as resp:
                    pass
            except Exception:
                pass

            time.sleep(240)

    t = threading.Thread(target=_pinger_loop, daemon=True)
    t.start()


# --- BOT SUPERVISOR ---
def run_supervisor():
    """Runs the bot and API server, restarting them if they crash."""
    # Detect python executable (local .venv vs global/container)
    venv_python = sys.executable
    if os.path.exists(".venv"):
        candidate = os.path.join(".venv", "Scripts", "python.exe") if os.name == 'nt' else os.path.join(".venv", "bin", "python")
        if os.path.isfile(candidate):
            venv_python = candidate

    print("--- Starting KuramaBot Supervisor ---")
    start_keep_alive_pinger()
    
    bot_proc = None
    api_proc = None
    
    try:
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Launching Telegram Bot and API Server...")
        
        # Start Telegram Bot
        bot_proc = subprocess.Popen([venv_python, "bot.py"])
        
        # Start FastAPI Server (handles webhooks and cloud health checks)
        api_proc = subprocess.Popen([venv_python, "api_server.py"])
        
        while True:
            # Check if either process crashed
            bot_ret = bot_proc.poll()
            api_ret = api_proc.poll()
            
            if bot_ret is not None:
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Bot crashed with exit code {bot_ret}. Restarting in 5 seconds...")
                time.sleep(5)
                bot_proc = subprocess.Popen([venv_python, "bot.py"])
                
            if api_ret is not None:
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] API Server crashed with exit code {api_ret}. Restarting in 5 seconds...")
                time.sleep(5)
                api_proc = subprocess.Popen([venv_python, "api_server.py"])
                
            time.sleep(5)
            
    except KeyboardInterrupt:
        print("\nSupervisor stopped by user. Terminating child processes...")
        if bot_proc: bot_proc.terminate()
        if api_proc: api_proc.terminate()
    except Exception as e:
        print(f"Supervisor encountered an error: {e}")
        if bot_proc: bot_proc.terminate()
        if api_proc: api_proc.terminate()

if __name__ == "__main__":
    run_supervisor()
