#!/bin/bash
set -e

# Normalize script line endings (handle Windows CRLF)
find /workspace/scripts -type f \( -name "*.sh" -o -name "*.py" \) -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

# ── Git Setup ──────────────────────────────────────────────────────
cd /workspace
if [ ! -d ".git" ]; then
    echo "Initializing new git repository..."
    git init
    git config user.email "ansible@local.derix.icu"
    git config user.name "Proxmox Deployer"
    echo "Git repository initialized."
else
    echo "Git repository already exists."
fi

# ── SSH Key Import (Host -> Container) ───────────────────────────
# If host SSH keys are mounted at /host_ssh, copy them into /root/.ssh
# with strict permissions so OpenSSH clients can use them.
if [ -d "/host_ssh" ]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    for key in /host_ssh/id_*; do
        [ -f "$key" ] || continue
        case "$key" in
            *.pub) continue ;;
        esac
        cp "$key" /root/.ssh/ 2>/dev/null || true
    done

    for pub in /host_ssh/*.pub; do
        [ -f "$pub" ] || continue
        cp "$pub" /root/.ssh/ 2>/dev/null || true
    done

    [ -f /host_ssh/config ] && cp /host_ssh/config /root/.ssh/config || true
    [ -f /host_ssh/known_hosts ] && cp /host_ssh/known_hosts /root/.ssh/known_hosts || true

    find /root/.ssh -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \; 2>/dev/null || true
    [ -f /root/.ssh/config ] && chmod 600 /root/.ssh/config || true
    [ -f /root/.ssh/known_hosts ] && chmod 644 /root/.ssh/known_hosts || true

    echo "Imported host SSH keys into container (/root/.ssh)."
fi

# ── Export variables for Packer (PKR_VAR_ prefix) ─────────────────
export PKR_VAR_proxmox_url="${PROXMOX_URL}"
export PKR_VAR_proxmox_api_token_id="${PROXMOX_API_TOKEN_ID}"
export PKR_VAR_proxmox_api_token_secret="${PROXMOX_API_TOKEN_SECRET}"
export PKR_VAR_proxmox_node="${PROXMOX_NODE}"
export PKR_VAR_ssh_public_key="${SSH_PUBLIC_KEY}"

# ── HTTP Server IP for Packer kickstart ────────────────────────────
# Detect the host IP that Proxmox VMs can reach during kickstart
# On WSL2, this is the Windows host IP; on Linux it's the local network IP
if [ -z "${PKR_VAR_http_server_ip}" ]; then
    # Try WSL2: Get Windows host IP from resolve.conf nameserver
    if grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
        HTTP_IP=$(grep -m 1 "nameserver" /etc/resolv.conf | awk '{print $2}')
    fi

    # Fallback: Try to get local network IP
    if [ -z "${HTTP_IP}" ]; then
        HTTP_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    # Last fallback: use local interface IP
    if [ -z "${HTTP_IP}" ]; then
        HTTP_IP=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | head -1)
    fi

    # If still empty, default to localhost (will fail but better than crashing)
    if [ -z "${HTTP_IP}" ]; then
        HTTP_IP="localhost"
    fi

    export PKR_VAR_http_server_ip="${HTTP_IP}"
fi

# ── Export variables for Terraform (TF_VAR_ prefix) ───────────────
export TF_VAR_proxmox_url="${PROXMOX_URL}"
export TF_VAR_proxmox_api_token_id="${PROXMOX_API_TOKEN_ID}"
export TF_VAR_proxmox_api_token_secret="${PROXMOX_API_TOKEN_SECRET}"
export TF_VAR_proxmox_node="${PROXMOX_NODE}"
export TF_VAR_ssh_public_key="${SSH_PUBLIC_KEY}"

echo ""
echo "============================================"
echo "  Proxmox VM Deployment Environment Ready"
echo "============================================"
echo "  Packer:    $(packer --version)"
echo "  Terraform: $(terraform --version | head -1)"
echo "  Ansible:   $(ansible --version | head -1)"
echo "  Python:    $(python3 --version)"
echo "============================================"
echo ""

exec "$@"

