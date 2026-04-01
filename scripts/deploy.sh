#!/bin/bash
set -euo pipefail

# ── Proxmox VM Deployment Pipeline ────────────────────────────────
# Usage: ./scripts/deploy.sh [phase1|phase2|phase3|all]

PHASE="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# ── Phase 1: Test Proxmox API ─────────────────────────────────────
phase1() {
    log "═══ Phase 1: Testing Proxmox API Connectivity ═══"
    python3 "$PROJECT_DIR/scripts/test_proxmox_api.py"
    ok "Phase 1 complete"
}

# ── Phase 2: Build Packer Template ────────────────────────────────
phase2() {
    log "═══ Phase 2: Building Packer Template ═══"
    cd "$PROJECT_DIR/packer"

    log "Initializing Packer plugins..."
    packer init .

    log "Validating Packer template..."
    packer validate .

    log "Building Proxmox template (this may take 15-30 minutes)..."
    packer build -force .

    ok "Phase 2 complete - Template created"
    warn "Note the template VM ID from the output above"
    warn "You will need it for Phase 3 (template_vm_id variable)"
}

# ── Phase 3: Deploy VMs with Terraform ────────────────────────────
phase3() {
    log "═══ Phase 3: Deploying VMs with Terraform ═══"
    cd "$PROJECT_DIR/terraform"

    if [ -z "${TF_VAR_template_vm_id:-}" ]; then
        echo ""
        warn "template_vm_id not set. Enter the VM ID of the Packer template:"
        read -rp "Template VM ID: " TEMPLATE_ID
        export TF_VAR_template_vm_id="$TEMPLATE_ID"
    fi

    if [ -z "${TF_VAR_vm_count:-}" ]; then
        echo ""
        warn "How many VMs to deploy? (default: 1)"
        read -rp "VM count [1]: " VM_COUNT
        export TF_VAR_vm_count="${VM_COUNT:-1}"
    fi

    log "Initializing Terraform..."
    terraform init

    log "Planning deployment..."
    terraform plan -out=tfplan

    echo ""
    log "Review the plan above. Continue? (yes/no)"
    read -rp "Apply? [yes]: " CONFIRM
    if [ "${CONFIRM:-yes}" != "yes" ]; then
        warn "Deployment cancelled"
        exit 0
    fi

    log "Applying Terraform plan..."
    terraform apply tfplan

    log "Deployment outputs:"
    terraform output

    ok "Phase 3 complete - VMs deployed and configured"
}

# ── Main ──────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════╗"
echo "║    Proxmox VM Deployment Pipeline               ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

case "$PHASE" in
    phase1|1) phase1 ;;
    phase2|2) phase1 && phase2 ;;
    phase3|3) phase3 ;;
    all)
        phase1
        echo ""
        phase2
        echo ""
        phase3
        ;;
    *)
        echo "Usage: $0 [phase1|phase2|phase3|all]"
        echo ""
        echo "  phase1  - Test Proxmox API connectivity"
        echo "  phase2  - Build Packer template (runs phase1 first)"
        echo "  phase3  - Deploy VMs with Terraform + Ansible"
        echo "  all     - Run all phases in sequence"
        exit 1
        ;;
esac
