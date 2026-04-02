#!/usr/bin/env python3
"""
Launcher script for Proxmox Deployment Web Dashboard
Opens the dashboard in the default browser and starts the Flask server.
"""

import sys
import subprocess
import webbrowser
import time
import os
from pathlib import Path

def main():
    # Check Python version
    if sys.version_info < (3, 8):
        print("❌ Error: Python 3.8 or higher is required")
        sys.exit(1)
    
    # Check if Flask is installed
    try:
        import flask
    except ImportError:
        print("❌ Error: Flask is not installed")
        print("\nInstall dependencies with:")
        print("  pip install -r requirements-web.txt")
        sys.exit(1)
    
    # Check if Docker is available
    try:
        subprocess.run(["docker", "--version"], capture_output=True, check=True, timeout=5)
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        print("❌ Error: Docker is not installed or not running")
        print("\nPlease ensure Docker Desktop is running")
        sys.exit(1)
    
    # Check if .env file exists
    env_file = Path.cwd() / ".env"
    if not env_file.exists():
        print("❌ Error: .env file not found")
        print("\nPlease copy .env.example to .env and configure it:")
        print("  cp .env.example .env")
        sys.exit(1)
    
    print("\n" + "="*60)
    print("  🖥️  Proxmox Deployment Web Dashboard")
    print("="*60)
    print("  🚀 Starting server...")
    print("="*60 + "\n")
    
    # Give user time to read message
    time.sleep(1)
    
    # Open browser after a delay (Flask needs time to start)
    def open_browser():
        time.sleep(2)
        print("  🌐 Opening browser at http://localhost:5000")
        webbrowser.open('http://localhost:5000')
    
    browser_thread = subprocess.Popen(
        [sys.executable, "-c", 
         "import time, webbrowser; time.sleep(2); webbrowser.open('http://localhost:5000')"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    
    try:
        # Run Flask app
        subprocess.run([sys.executable, "app.py"], cwd=str(Path.cwd()))
    except KeyboardInterrupt:
        print("\n\n✅ Dashboard stopped")
    except Exception as e:
        print(f"\n❌ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
