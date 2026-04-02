@echo off
REM Proxmox Deployment Web Dashboard Launcher for Windows
REM This script starts the Flask server and opens the dashboard in your browser

setlocal enabledelayedexpansion

cd /d "%~dp0"

REM Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Error: Python is not installed or not in PATH
    echo Please install Python from https://www.python.org/
    pause
    exit /b 1
)

REM Check Docker
docker --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Error: Docker is not running or not installed
    echo Please ensure Docker Desktop is running
    pause
    exit /b 1
)

REM Check .env
if not exist .env (
    echo ❌ Error: .env file not found
    echo Please copy .env.example to .env first
    pause
    exit /b 1
)

REM Check and install dependencies
echo 📦 Checking dependencies...
python -c "import flask; import flask_cors" >nul 2>&1
if errorlevel 1 (
    echo Installing Flask and dependencies...
    pip install -q -r requirements-web.txt
    if errorlevel 1 (
        echo ❌ Failed to install dependencies
        echo Try: pip install -r requirements-web.txt
        pause
        exit /b 1
    )
)

REM Start the dashboard
echo.
echo ============================================================
echo   🖥️  Proxmox Deployment Web Dashboard
echo ============================================================
echo   🌐 Opening http://localhost:5000 in your browser...
echo   🔴 Press Ctrl+C to stop the server
echo ============================================================
echo.

python app.py

pause
