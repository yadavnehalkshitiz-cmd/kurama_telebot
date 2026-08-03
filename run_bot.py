import subprocess
import time
import sys
import os
import signal

# --- BOT SUPERVISOR ---
def run_supervisor():
    """Runs the bot and API server, restarting them if they crash."""
    # Detect python executable (local .venv vs global/container)
    if os.path.exists(".venv"):
        venv_python = os.path.join(".venv", "Scripts", "python.exe") if os.name == 'nt' else os.path.join(".venv", "bin", "python")
    else:
        # If no venv, we assume we are in a container/server with global python
        venv_python = sys.executable

    print("--- Starting KuramaBot Supervisor ---")
    
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
