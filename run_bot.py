import subprocess
import time
import sys
import os
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

# --- TINY WEB SERVER FOR CLOUD HEALTH CHECKS ---
# This prevents cloud services (like Hugging Face) from stopping the bot 
# because it's not listening on any port.
class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(b"Bot is Running!")

    def log_message(self, format, *args):
        # Silence the logs to keep the terminal clean
        return

def run_health_server():
    # Hugging Face and others use port 7860 or 8080.
    # We default to 7860 (Hugging Face default) or whatever the PORT env var says.
    port = int(os.environ.get("PORT", 7860))
    server = HTTPServer(("0.0.0.0", port), HealthCheckHandler)
    print(f"Health check server started on port {port}")
    server.serve_forever()

# --- BOT SUPERVISOR ---
def run_bot():
    """Runs the bot and restarts it if it crashes."""
    # Start health check in a background thread so it doesn't block the bot
    threading.Thread(target=run_health_server, daemon=True).start()

    # Detect python executable (local .venv vs global/container)
    if os.path.exists(".venv"):
        venv_python = os.path.join(".venv", "Scripts", "python.exe") if os.name == 'nt' else os.path.join(".venv", "bin", "python")
    else:
        # If no venv, we assume we are in a container/server with global python
        venv_python = sys.executable

    print("--- Starting Bot Supervisor ---")
    while True:
        try:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Launching bot...")
            # Use subprocess to run the bot script
            process = subprocess.Popen([venv_python, "bot.py"])
            
            # Wait for the process to finish
            process.wait()
            
            if process.returncode != 0:
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Bot crashed with exit code {process.returncode}. Restarting in 5 seconds...")
            else:
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Bot stopped normally. Restarting in 5 seconds...")
                
            time.sleep(5)
        except KeyboardInterrupt:
            print("\nSupervisor stopped by user.")
            process.terminate()
            break
        except Exception as e:
            print(f"Supervisor encountered an error: {e}")
            time.sleep(10)

if __name__ == "__main__":
    run_bot()
