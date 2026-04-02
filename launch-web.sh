#!/bin/bash
# Proxmox Deployment Web Dashboard Launcher for macOS and Linux

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🖥️  Proxmox Deployment Web Dashboard Launcher"
echo ""

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python 3 is not installed"
    echo "Please install Python 3 from https://www.python.org/"
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>&1)
echo "🐍 $PYTHON_VERSION found"

# Check Docker
if ! docker --version &> /dev/null; then
    echo "❌ Error: Docker is not installed or not running"
    echo "Please install Docker from https://www.docker.com/"
    exit 1
fi

echo "🐳 Docker is running"

# Check .env
if [ ! -f ".env" ]; then
    echo "❌ Error: .env file not found"
    echo "Please copy .env.example to .env first"
    exit 1
fi

# Check dependencies
echo "📦 Checking dependencies..."
if ! python3 -c "import flask; import flask_cors" 2>/dev/null; then
    echo "Installing Flask and dependencies..."
    if ! pip3 install -r requirements-web.txt; then
        echo "❌ Failed to install dependencies"
        echo "Try: pip3 install -r requirements-web.txt"
        exit 1
    fi
fi

echo ""
echo "============================================================"
echo "  🖥️  Proxmox Deployment Web Dashboard"
echo "============================================================"
echo "  🌐 Opening http://localhost:5000 in your browser..."
echo "  🔴 Press Ctrl+C to stop the server"
echo "============================================================"
echo ""

# Open browser in background (cross-platform)
(sleep 2 && {
    if command -v xdg-open &> /dev/null; then
        xdg-open http://localhost:5000
    elif command -v open &> /dev/null; then
        open http://localhost:5000
    fi
}) &

# Start Flask server
python3 app.py
