@echo off
TITLE Kurama Telebot - One Click Run
:: Navigate to the directory where the script is located
cd /d "%~dp0"

echo ==========================================
echo    Kurama Telebot - Bot Supervisor
echo ==========================================
echo.

:: Check if virtual environment exists
if exist .venv\Scripts\python.exe (
    echo [INFO] Using virtual environment...
    .venv\Scripts\python.exe run_bot.py
) else (
    echo [WARN] .venv NOT FOUND!
    echo [INFO] Attempting to run with system python...
    python run_bot.py
)

:: If it fails, keep the window open so the user can see why
if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] The bot crashed or could not start.
    echo Please check if you have installed the requirements:
    echo pip install -r requirements.txt
)

echo.
echo ==========================================
echo    Bot Process Ended.
echo ==========================================
pause
