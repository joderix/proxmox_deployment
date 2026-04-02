#!/usr/bin/env pwsh
Set-Location -Path "C:\Users\John\projects\proxmox_deployment"
Write-Host "Running network diagnostics inside container..."
Write-Host ""

docker compose run --rm deployer bash -c @'
set -e
echo "========================================"
echo "  Network Diagnostics"
echo "========================================"
echo ""

# Extract values from environment
PROXMOX_URL="${PROXMOX_URL}"
PROXMOX_HOST=$(echo "$PROXMOX_URL" | sed -E 's|https?://([^:]+).*|\1|')
PROXMOX_PORT=$(echo "$PROXMOX_URL" | sed -E 's|.*:([0-9]+).*|\1|' || echo "8006")

echo "[1] Environment variables"
echo "    PROXMOX_URL=$PROXMOX_URL"
echo "    Extracted host: $PROXMOX_HOST"
echo "    Extracted port: $PROXMOX_PORT"
echo ""

echo "[2] DNS Resolution Test"
if nslookup "$PROXMOX_HOST" > /dev/null 2>&1; then
    IP=$(nslookup "$PROXMOX_HOST" | grep -A1 "Name:" | tail -1 | awk '{print $NF}')
    echo "    [PASS] Resolved $PROXMOX_HOST -> $IP"
else
    echo "    [FAIL] Cannot resolve $PROXMOX_HOST"
    echo "    Trying /etc/hosts..."
    grep "$PROXMOX_HOST" /etc/hosts || echo "    Not in /etc/hosts"
fi
echo ""

echo "[3] Network Connectivity Test (ping)"
if ping -c 3 "$PROXMOX_HOST" > /dev/null 2>&1; then
    echo "    [PASS] Host is reachable"
else
    echo "    [FAIL] Host unreachable (may be blocked by firewall or host firewall)"
fi
echo ""

echo "[4] Port 8006 Test (timeout 5s)"
if timeout 5 bash -c "</dev/tcp/$PROXMOX_HOST/8006" 2>/dev/null; then
    echo "    [PASS] Port 8006 is open and reachable"
else
    echo "    [FAIL] Port 8006 is not reachable"
    echo "    Possible causes:"
    echo "    - Proxmox is not running"
    echo "    - Port 8006 is not the correct port"
    echo "    - Firewall is blocking the connection"
    echo "    - Wrong hostname/IP address"
fi
echo ""

echo "[5] HTTPS Connection Test (curl)"
curl -v --max-time 5 --insecure "https://$PROXMOX_HOST:$PROXMOX_PORT/api2/json/version" 2>&1 | head -30 || echo "    [INFO] Connection failed (expected if port unreachable)"
echo ""

echo "[6] Routing Information"
echo "    Default route:"
ip route | grep default
echo ""
echo "    All routes:"
ip route
echo ""

echo "========================================"
echo "  Diagnostics Complete"
echo "========================================"
'@

Write-Host "Exit code: $LASTEXITCODE"
