# Platform notes:
# - Linux: network_mode: host works perfectly
# - WSL2: network_mode: host works (treated as Linux)
# - macOS: Use bridge network with extra_hosts for local network access

# Detect platform and uncomment appropriate section below

# ════════════════════════════════════════════════════════════════════════════
# FOR LINUX and WSL2 (recommended - full host network access)
# ════════════════════════════════════════════════════════════════════════════
services:
  deployer:
    build: .
    container_name: proxmox-deployer
    volumes:
      - ./:/workspace
    env_file:
      - .env
    stdin_open: true
    tty: true
    network_mode: host  # Works on Linux and WSL2

# ════════════════════════════════════════════════════════════════════════════
# ALTERNATIVE: FOR macOS (Docker Desktop)
# Replace the above 'deployer' service with this if on macOS:
# ════════════════════════════════════════════════════════════════════════════
# services:
#   deployer:
#     build: .
#     container_name: proxmox-deployer
#     volumes:
#       - ./:/workspace
#     env_file:
#       - .env
#     stdin_open: true
#     tty: true
#     networks:
#       - bridge-net
#     extra_hosts:
#       - "host.docker.internal:host-gateway"
#       - "proxmox:192.168.3.23"  # Direct IP mapping for Proxmox
#       - "pve03:192.168.3.23"
#
# networks:
#   bridge-net:
#     driver: bridge
#
# ════════════════════════════════════════════════════════════════════════════
# If Packer HTTP server still unreachable on macOS Phase 2, set in .env:
#   PACKER_HTTP_IP=192.168.3.X  (your host machine's local IP, not 127.0.0.1)
# ════════════════════════════════════════════════════════════════════════════
