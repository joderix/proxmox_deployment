# Proxmox Deployment Web Dashboard Launcher for Windows PowerShell
# Run with: powershell -ExecutionPolicy Bypass -File launch-web.ps1

$ErrorActionPreference = "Continue"

Write-Host "🖥️  Proxmox Deployment Web Dashboard Launcher" -ForegroundColor Cyan

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Check Python
try {
    $PythonVersion = python --version 2>&1
    Write-Host "🐍 $PythonVersion found" -ForegroundColor Green
}
catch {
    Write-Host "❌ Error: Python is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Python from https://www.python.org/" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Check Docker
try {
    docker --version | Out-Null
    Write-Host "🐳 Docker is running" -ForegroundColor Green
}
catch {
    Write-Host "❌ Error: Docker is not running" -ForegroundColor Red
    Write-Host "Please ensure Docker Desktop is running" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Check .env
if (-not (Test-Path ".env")) {
    Write-Host "❌ Error: .env file not found" -ForegroundColor Red
    Write-Host "Please copy .env.example to .env first" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Check dependencies
Write-Host "📦 Checking dependencies..." -ForegroundColor Cyan
$CheckCmd = "import flask; import flask_cors"
$Output = python -c $CheckCmd 2>&1
$PythonExitCode = $LASTEXITCODE

if ($PythonExitCode -ne 0) {
    Write-Host "Installing Flask and dependencies..." -ForegroundColor Yellow
    pip install -r requirements-web.txt
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to install dependencies" -ForegroundColor Red
        Write-Host "Try: pip install -r requirements-web.txt" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host "  🖥️  Proxmox Deployment Web Dashboard" -ForegroundColor Cyan
Write-Host "============================================================"
Write-Host "  🌐 Opening http://localhost:5000 in your browser..."
Write-Host "  🔴 Press Ctrl+C to stop the server"
Write-Host "============================================================"
Write-Host ""

# Start the dashboard
python app.py

Read-Host "Press Enter to exit"
