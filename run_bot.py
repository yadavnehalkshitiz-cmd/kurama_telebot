import subprocess
import time
import sys
import os

def run_bot():
    """Runs the bot and restarts it if it crashes."""
    # Detect python executable
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
