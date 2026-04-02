#!/usr/bin/env python3
"""
Proxmox Deployment Web UI - Modern web-based dashboard
Flask backend for deployment pipeline management with real-time logging.
"""

import sys
import os
import subprocess
import threading
import socket
import re
from datetime import datetime
from pathlib import Path
from queue import Queue
import json

from flask import Flask, render_template, jsonify, request, send_from_directory
from flask_cors import CORS


app = Flask(__name__, template_folder='templates', static_folder='static')
CORS(app)

# Global state
task_queue = Queue()
current_process = None
current_container_name = None
is_task_running = False
logs = []

DEFAULT_TEMPLATE_PROFILE_MAP = {
    "9104": "fedora",
    "9204": "ubuntu",
}

TEMPLATE_PROFILE_MAP_FILE = Path.cwd() / "config" / "template_profile_map.json"

PROFILE_ENV_FILES = {
    "fedora": ".env.fedora",
    "ubuntu": ".env.ubuntu",
}


def normalize_profile(raw_value: str) -> str:
    """Normalize incoming profile names to supported values."""
    value = (raw_value or "fedora").strip().lower()
    return value if value in {"fedora", "ubuntu"} else "fedora"


def load_template_profile_map() -> dict[str, str]:
    """Load template-id -> profile mapping from JSON config with safe fallback."""
    if not TEMPLATE_PROFILE_MAP_FILE.exists():
        return DEFAULT_TEMPLATE_PROFILE_MAP.copy()

    try:
        with TEMPLATE_PROFILE_MAP_FILE.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return DEFAULT_TEMPLATE_PROFILE_MAP.copy()

        mapping: dict[str, str] = {}
        for raw_id, raw_profile in data.items():
            template_id = str(raw_id).strip()
            profile = normalize_profile(str(raw_profile))
            if template_id.isdigit():
                mapping[template_id] = profile

        return mapping or DEFAULT_TEMPLATE_PROFILE_MAP.copy()
    except Exception:
        return DEFAULT_TEMPLATE_PROFILE_MAP.copy()


def compose_base_cmd(profile: str) -> list[str]:
    """Build docker compose base command with optional profile env file."""
    cmd = ["docker", "compose"]
    profile_env = PROFILE_ENV_FILES.get(profile, "")
    if profile_env and (Path.cwd() / profile_env).exists():
        cmd.extend(["--env-file", profile_env])
    return cmd


def resolve_profile_for_template(requested_profile: str, template_vm_id: str) -> str:
    """Resolve profile from template ID map, overriding selected profile when known."""
    mapped_profile = load_template_profile_map().get(template_vm_id.strip())
    if mapped_profile and mapped_profile != requested_profile:
        add_log(
            f"Template {template_vm_id} is mapped to '{mapped_profile}', overriding selected profile '{requested_profile}'",
            "warning"
        )
        return mapped_profile
    return mapped_profile or requested_profile


def add_log(message: str, level: str = "info"):
    """Add a log message to the log list."""
    timestamp = datetime.now().strftime("%H:%M:%S")
    log_entry = {
        "timestamp": timestamp,
        "level": level,
        "message": message
    }
    logs.append(log_entry)
    # Keep only last 500 logs to avoid memory bloat
    if len(logs) > 500:
        logs.pop(0)
    print(f"[{timestamp}] {level.upper()}: {message}")


def run_command_sync(cmd, description, container_name=None):
    """Run a command synchronously and capture output."""
    global current_process, current_container_name, is_task_running

    try:
        add_log(f"Starting: {description}", "info")

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True,
            encoding='utf-8',
            errors='replace',
            cwd=str(Path.cwd())
        )
        current_process = process
        current_container_name = container_name

        # Stream output line by line
        for line in process.stdout:
            line = line.rstrip()
            if line:
                add_log(line, "output")

        returncode = process.wait()
        current_process = None
        current_container_name = None

        if returncode == 0:
            add_log(f"✅ {description} completed successfully", "success")
            return True
        else:
            add_log(f"❌ {description} failed with exit code {returncode}", "error")
            return False

    except Exception as e:
        add_log(f"❌ {description} error: {str(e)}", "error")
        return False

    finally:
        current_process = None
        current_container_name = None
        is_task_running = False


def run_task_thread(cmd, description, container_name=None):
    """Run task in a background thread."""
    global is_task_running
    is_task_running = True
    run_command_sync(cmd, description, container_name)


def _make_run_container_name(phase: str) -> str:
    """Build a unique container name for docker compose run so cancellation can target it."""
    ts = datetime.now().strftime("%Y%m%d%H%M%S")
    return f"proxmox-{phase}-{ts}"


def _pick_free_port(start: int = 18080, end: int = 18150) -> int:
    """Pick a free TCP port on the host in a constrained range."""
    docker_ports = _get_docker_published_ports()
    for port in range(start, end + 1):
        if port in docker_ports:
            continue
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                sock.bind(("0.0.0.0", port))
                return port
            except OSError:
                continue
    raise RuntimeError(f"No free TCP port found in range {start}-{end}")


def _get_docker_published_ports() -> set[int]:
    """Return host ports currently published by running Docker containers."""
    try:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.Ports}}"],
            capture_output=True,
            text=True,
            encoding='utf-8',
            errors='replace',
            check=False,
            timeout=10
        )
        ports: set[int] = set()
        if result.returncode != 0:
            return ports

        for line in result.stdout.splitlines():
            # Matches both IPv4 and IPv6 mappings like:
            # 0.0.0.0:18080->18080/tcp, [::]:18080->18080/tcp
            for match in re.findall(r":(\d+)->", line):
                try:
                    ports.add(int(match))
                except ValueError:
                    continue
        return ports
    except Exception:
        return set()


def _cleanup_stale_phase2_containers() -> int:
    """Remove stale project run containers that can keep old ports allocated."""
    removed = 0
    prefixes = ["proxmox-phase2-", "proxmox_deployment-deployer-run-"]
    for prefix in prefixes:
        try:
            result = subprocess.run(
                [
                    "docker", "ps", "-a",
                    "--filter", f"name={prefix}",
                    "--format", "{{.ID}}"
                ],
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='replace',
                check=False,
                timeout=10
            )
            if result.returncode != 0:
                continue

            for cid in [x.strip() for x in result.stdout.splitlines() if x.strip()]:
                rm = subprocess.run(
                    ["docker", "rm", "-f", cid],
                    capture_output=True,
                    text=True,
                    encoding='utf-8',
                    errors='replace',
                    check=False,
                    timeout=10
                )
                if rm.returncode == 0:
                    removed += 1
        except Exception:
            continue
    return removed


@app.route('/')
def index():
    """Serve the main UI."""
    return render_template('index.html')


@app.route('/api/status')
def get_status():
    """Get current status."""
    return jsonify({
        "is_running": is_task_running,
        "log_count": len(logs)
    })


@app.route('/api/logs')
def get_logs():
    """Get all logs."""
    return jsonify(logs)


@app.route('/api/template-profile-map')
def get_template_profile_map():
    """Expose template-id to profile mapping for UI auto-selection."""
    return jsonify(load_template_profile_map())


@app.route('/api/logs/clear', methods=['POST'])
def clear_logs():
    """Clear all logs."""
    global logs
    logs = []
    add_log("Logs cleared", "info")
    return jsonify({"status": "cleared"})


@app.route('/api/cancel', methods=['POST'])
def cancel_task():
    """Cancel the running task."""
    global current_process, current_container_name, is_task_running

    if not is_task_running:
        return jsonify({"error": "No task running"}), 400

    try:
        add_log("Cancelling task...", "warning")

        # First, signal the containerized process (Terraform/Packer) directly.
        if current_container_name:
            add_log(f"Sending SIGINT to container {current_container_name}", "warning")
            kill_result = subprocess.run(
                ["docker", "kill", "--signal=SIGINT", current_container_name],
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='replace',
                check=False,
                timeout=10
            )
            if kill_result.returncode == 0:
                add_log("Interrupt signal sent to running container", "info")
            else:
                add_log("Container not running or signal could not be delivered", "warning")

            # Ensure the run container is not left behind.
            subprocess.run(
                ["docker", "rm", "-f", current_container_name],
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='replace',
                check=False,
                timeout=10
            )

        # Then terminate the local docker compose client process if still running.
        if current_process and current_process.poll() is None:
            current_process.terminate()

        # Give it 5 seconds to terminate gracefully
        try:
            if current_process:
                current_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            add_log("Force killing process after timeout", "warning")
            if current_process and current_process.poll() is None:
                current_process.kill()
                current_process.wait()

        add_log("Task cancelled by user", "warning")
        current_process = None
        current_container_name = None
        is_task_running = False
        return jsonify({"status": "cancelled"})

    except Exception as e:
        add_log(f"Error cancelling task: {str(e)}", "error")
        return jsonify({"error": str(e)}), 500


@app.route('/api/tasks/build', methods=['POST'])
def task_build():
    """Build and start the Docker container."""
    global is_task_running

    if is_task_running:
        return jsonify({"error": "A task is already running"}), 400

    data = request.get_json(silent=True) or {}
    profile = normalize_profile(str(data.get("profile", "fedora")))
    compose_cmd = compose_base_cmd(profile)

    thread = threading.Thread(
        target=run_task_thread,
        args=(compose_cmd + ["build"], f"Building Docker image ({profile})"),
        daemon=True
    )
    thread.start()

    return jsonify({"status": "started"})


@app.route('/api/tasks/phase1', methods=['POST'])
def task_phase1():
    """Run Phase 1: API connectivity test."""
    global is_task_running

    if is_task_running:
        return jsonify({"error": "A task is already running"}), 400

    data = request.get_json(silent=True) or {}
    profile = normalize_profile(str(data.get("profile", "fedora")))
    compose_cmd = compose_base_cmd(profile)

    container_name = _make_run_container_name("phase1")
    thread = threading.Thread(
        target=run_task_thread,
        args=(compose_cmd + [
            "run", "--rm", "--name", container_name,
            "-e", f"PROJECT_PROFILE={profile}",
            "deployer", "./scripts/deploy.sh", "phase1"
        ], f"Phase 1: API Connectivity Test ({profile})", container_name),
        daemon=True
    )
    thread.start()

    return jsonify({"status": "started"})


@app.route('/api/tasks/phase2', methods=['POST'])
def task_phase2():
    """Run Phase 2: Packer template build."""
    global is_task_running

    if is_task_running:
        return jsonify({"error": "A task is already running"}), 400

    data = request.get_json(silent=True) or {}
    profile = normalize_profile(str(data.get("profile", "fedora")))
    compose_cmd = compose_base_cmd(profile)

    removed = _cleanup_stale_phase2_containers()
    if removed > 0:
        add_log(f"Cleaned up {removed} stale run container(s)", "info")

    container_name = _make_run_container_name("phase2")
    phase2_port = _pick_free_port()
    add_log(
        f"Using host port {phase2_port} for Packer HTTP server (kickstart)",
        "info"
    )

    thread = threading.Thread(
        target=run_task_thread,
        args=(compose_cmd + [
            "run", "--rm", "--name", container_name,
            "--publish", f"{phase2_port}:{phase2_port}",
            "-e", f"PKR_VAR_http_server_port={phase2_port}",
            "-e", f"PROJECT_PROFILE={profile}",
            "deployer", "./scripts/deploy.sh", "phase2"
        ], f"Phase 2: Packer Template Build ({profile}, 15-30 min)", container_name),
        daemon=True
    )
    thread.start()

    return jsonify({"status": "started"})


@app.route('/api/tasks/phase3', methods=['POST'])
def task_phase3():
    """Run Phase 3: Terraform deployment."""
    global is_task_running

    if is_task_running:
        return jsonify({"error": "A task is already running"}), 400

    data = request.get_json(silent=True) or {}
    profile = normalize_profile(str(data.get("profile", "fedora")))
    template_vm_id = str(data.get("template_vm_id", "")).strip()
    vm_count = str(data.get("vm_count", "1")).strip() or "1"

    if not template_vm_id or not template_vm_id.isdigit():
        return jsonify({"error": "template_vm_id is required and must be a number"}), 400
    if not vm_count.isdigit() or int(vm_count) < 1:
        return jsonify({"error": "vm_count must be a positive number"}), 400

    profile = resolve_profile_for_template(profile, template_vm_id)
    compose_cmd = compose_base_cmd(profile)

    container_name = _make_run_container_name("phase3")
    add_log(
        f"Phase 3 ({profile}): deploying {vm_count} VM(s) from template {template_vm_id}",
        "info"
    )

    thread = threading.Thread(
        target=run_task_thread,
        args=(compose_cmd + [
            "run", "--rm", "--name", container_name,
            "-e", f"TF_VAR_template_vm_id={template_vm_id}",
            "-e", f"TF_VAR_vm_count={vm_count}",
            "-e", "TF_AUTO_APPROVE=1",
            "-e", f"PROJECT_PROFILE={profile}",
            "deployer", "./scripts/deploy.sh", "phase3"
        ], f"Phase 3: Terraform VM Deployment ({profile})", container_name),
        daemon=True
    )
    thread.start()

    return jsonify({"status": "started"})


@app.route('/api/tasks/phase3/plan', methods=['POST'])
def task_phase3_plan():
    """Run Phase 3 Terraform plan only (dry-run)."""
    global is_task_running

    if is_task_running:
        return jsonify({"error": "A task is already running"}), 400

    data = request.get_json(silent=True) or {}
    profile = normalize_profile(str(data.get("profile", "fedora")))
    template_vm_id = str(data.get("template_vm_id", "")).strip()
    vm_count = str(data.get("vm_count", "1")).strip() or "1"

    if not template_vm_id or not template_vm_id.isdigit():
        return jsonify({"error": "template_vm_id is required and must be a number"}), 400
    if not vm_count.isdigit() or int(vm_count) < 1:
        return jsonify({"error": "vm_count must be a positive number"}), 400

    profile = resolve_profile_for_template(profile, template_vm_id)
    compose_cmd = compose_base_cmd(profile)

    container_name = _make_run_container_name("phase3-plan")
    add_log(
        f"Phase 3 plan ({profile}): planning {vm_count} VM(s) from template {template_vm_id}",
        "info"
    )

    thread = threading.Thread(
        target=run_task_thread,
        args=(compose_cmd + [
            "run", "--rm", "--name", container_name,
            "-e", f"TF_VAR_template_vm_id={template_vm_id}",
            "-e", f"TF_VAR_vm_count={vm_count}",
            "-e", f"PROJECT_PROFILE={profile}",
            "deployer", "./scripts/deploy.sh", "phase3-plan"
        ], f"Phase 3: Terraform Plan Dry-Run ({profile})", container_name),
        daemon=True
    )
    thread.start()

    return jsonify({"status": "started"})


def main():
    """Entry point."""
    # Check Python version
    if sys.version_info < (3, 8):
        print("❌ Error: Python 3.8 or higher is required")
        sys.exit(1)

    # Check if Flask is installed
    try:
        import flask
    except ImportError:
        print("❌ Error: Flask is not installed")
        print("\nInstall it with:")
        print("  pip install flask flask-cors")
        sys.exit(1)

    # Check if Docker is available
    try:
        subprocess.run(["docker", "--version"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ Error: Docker is not installed or not in PATH")
        sys.exit(1)

    # Check if at least one environment file exists
    env_default = Path.cwd() / ".env"
    env_fedora = Path.cwd() / ".env.fedora"
    env_ubuntu = Path.cwd() / ".env.ubuntu"
    if not (env_default.exists() or env_fedora.exists() or env_ubuntu.exists()):
        print("❌ Error: no environment file found")
        print("\nCreate at least one of these files:")
        print("  .env")
        print("  .env.fedora")
        print("  .env.ubuntu")
        sys.exit(1)

    # Add initial log
    add_log("Proxmox Deployment Dashboard started", "success")

    # Start Flask app
    print("\n" + "="*50)
    print("  🖥️  Proxmox Deployment Dashboard")
    print("="*50)
    print("  🌐 Open browser: http://localhost:5000")
    print("  🔴 Press Ctrl+C to stop")
    print("="*50 + "\n")

    app.run(
        host='127.0.0.1',
        port=5000,
        debug=False,
        use_reloader=False
    )


if __name__ == '__main__':
    main()
