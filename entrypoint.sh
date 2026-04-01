#!/bin/bash
set -e

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

# ── Export variables for Packer (PKR_VAR_ prefix) ─────────────────
export PKR_VAR_proxmox_url="${PROXMOX_URL}"
export PKR_VAR_proxmox_api_token_id="${PROXMOX_API_TOKEN_ID}"
export PKR_VAR_proxmox_api_token_secret="${PROXMOX_API_TOKEN_SECRET}"
export PKR_VAR_proxmox_node="${PROXMOX_NODE}"
export PKR_VAR_ssh_public_key="${SSH_PUBLIC_KEY}"

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
