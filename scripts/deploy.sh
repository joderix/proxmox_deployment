#!/bin/bash
set -euo pipefail

# ── Proxmox VM Deployment Pipeline ────────────────────────────────
# Usage: ./scripts/deploy.sh [phase1|phase2|phase3|all]

PHASE="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_PROFILE="${PROJECT_PROFILE:-fedora}"

case "$PROJECT_PROFILE" in
    fedora)
        PROFILE_SUFFIX=""
        PROFILE_LABEL="fedora-cosmic-atomic"
        ;;
    ubuntu)
        PROFILE_SUFFIX="-ubuntu"
        PROFILE_LABEL="ubuntu"
        ;;
    *)
        echo "[✗] Unsupported PROJECT_PROFILE: $PROJECT_PROFILE"
        echo "    Allowed values: fedora, ubuntu"
        exit 1
        ;;
esac

PACKER_DIR="$PROJECT_DIR/packer$PROFILE_SUFFIX"
TERRAFORM_DIR="$PROJECT_DIR/terraform$PROFILE_SUFFIX"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

normalize_int() {
    local raw="$1"
    # Trim all whitespace and optional surrounding quotes.
    raw="$(echo "$raw" | tr -d '[:space:]')"
    raw="${raw%\"}"
    raw="${raw#\"}"
    raw="${raw%\'}"
    raw="${raw#\'}"
    echo "$raw"
}

check_proxmox_vm_exists() {
    local vmid="$1"
    local api_url="${PROXMOX_URL:-}"
    local node_name="${PROXMOX_NODE:-}"
    local token_id="${PROXMOX_API_TOKEN_ID:-}"
    local token_secret="${PROXMOX_API_TOKEN_SECRET:-}"

    if [ -z "$api_url" ] || [ -z "$node_name" ] || [ -z "$token_id" ] || [ -z "$token_secret" ]; then
        warn "Skipping pre-check for VMID $vmid (missing Proxmox API env vars in current shell)"
        return 0
    fi

    local url="${api_url%/}/nodes/${node_name}/qemu/${vmid}/status/current"
    local auth_header="Authorization: PVEAPIToken=${token_id}=${token_secret}"
    local response
    response="$(curl -ksS -H "$auth_header" "$url" 2>/dev/null || true)"

    if echo "$response" | grep -q '"data"'; then
        return 0
    fi
    return 1
}

prepare_phase2_inputs() {
    if [ "$PROJECT_PROFILE" != "ubuntu" ]; then
        return 0
    fi

    local base_cloud_image_vm_id
    base_cloud_image_vm_id="$(normalize_int "${PKR_VAR_base_cloud_image_vm_id:-}")"

    if [ -z "$base_cloud_image_vm_id" ]; then
        err "Ubuntu phase2 requires PKR_VAR_base_cloud_image_vm_id (VMID of imported Ubuntu cloud-image base template)."
    fi

    [[ "$base_cloud_image_vm_id" =~ ^[0-9]+$ ]] || err "PKR_VAR_base_cloud_image_vm_id must be a number, got: '${base_cloud_image_vm_id:-<empty>}'"
    export PKR_VAR_base_cloud_image_vm_id="$base_cloud_image_vm_id"

    log "Ubuntu clone source VMID: $PKR_VAR_base_cloud_image_vm_id"
    if ! check_proxmox_vm_exists "$PKR_VAR_base_cloud_image_vm_id"; then
        err "Base cloud-image VMID '$PKR_VAR_base_cloud_image_vm_id' was not found on node '$PROXMOX_NODE'. Import/create the Ubuntu base template first, then retry phase2."
    fi
}

# ── Phase 1: Test Proxmox API ─────────────────────────────────────
phase1() {
    log "═══ Phase 1: Testing Proxmox API Connectivity ($PROFILE_LABEL) ═══"
    python3 "$PROJECT_DIR/scripts/test_proxmox_api.py"
    ok "Phase 1 complete"
}

# ── Phase 2: Build Packer Template ────────────────────────────────
phase2() {
    log "═══ Phase 2: Building Packer Template ($PROFILE_LABEL) ═══"
    [ -d "$PACKER_DIR" ] || err "Packer directory not found: $PACKER_DIR"
    cd "$PACKER_DIR"

    prepare_phase2_inputs

    log "Initializing Packer plugins..."
    packer init .

    log "Validating Packer template..."
    packer validate .

    log "Building Proxmox template (this may take 15-30+ minutes)..."
    log "Using -on-error=abort so failed/time-out builds keep the VM for inspection"
    packer build -force -on-error=abort .

    ok "Phase 2 complete - Template created"
    warn "Note the template VM ID from the output above"
    warn "You will need it for Phase 3 (template_vm_id variable)"
}

prepare_phase3_inputs() {
    local template_vm_id="$(normalize_int "${TF_VAR_template_vm_id:-}")"
    if [ -z "$template_vm_id" ]; then
        echo ""
        warn "template_vm_id not set. Enter the VM ID of the Packer template:"
        read -rp "Template VM ID: " TEMPLATE_ID
        template_vm_id="$(normalize_int "$TEMPLATE_ID")"
    fi
    [[ "$template_vm_id" =~ ^[0-9]+$ ]] || err "template_vm_id must be a number, got: '${template_vm_id:-<empty>}'"
    export TF_VAR_template_vm_id="$template_vm_id"

    local vm_count="$(normalize_int "${TF_VAR_vm_count:-}")"
    if [ -z "$vm_count" ]; then
        echo ""
        warn "How many VMs to deploy? (default: 1)"
        read -rp "VM count [1]: " VM_COUNT
        vm_count="$(normalize_int "${VM_COUNT:-1}")"
    fi
    [[ "$vm_count" =~ ^[0-9]+$ ]] || err "vm_count must be a number, got: '${vm_count:-<empty>}'"
    [ "$vm_count" -ge 1 ] || err "vm_count must be >= 1, got: $vm_count"
    export TF_VAR_vm_count="$vm_count"
}

phase3_plan() {
    log "═══ Phase 3 Plan: Terraform Dry Run ($PROFILE_LABEL) ═══"
    [ -d "$TERRAFORM_DIR" ] || err "Terraform directory not found: $TERRAFORM_DIR"
    cd "$TERRAFORM_DIR"

    prepare_phase3_inputs

    log "Initializing Terraform..."
    terraform init

    log "Planning deployment (no changes will be applied)..."
    terraform plan -out=tfplan
    ok "Phase 3 plan complete - no infrastructure changes applied"
}

# ── Phase 3: Deploy VMs with Terraform ────────────────────────────
phase3() {
    log "═══ Phase 3: Deploying VMs with Terraform ($PROFILE_LABEL) ═══"
    [ -d "$TERRAFORM_DIR" ] || err "Terraform directory not found: $TERRAFORM_DIR"
    cd "$TERRAFORM_DIR"

    prepare_phase3_inputs

    log "Initializing Terraform..."
    terraform init

    log "Planning deployment..."
    terraform plan -out=tfplan

    if [ "${TF_AUTO_APPROVE:-}" = "1" ]; then
        log "Auto-approve enabled (web UI), applying plan..."
    else
        echo ""
        log "Review the plan above. Continue? (yes/no)"
        read -rp "Apply? [yes]: " CONFIRM
        if [ "${CONFIRM:-yes}" != "yes" ]; then
            warn "Deployment cancelled"
            exit 0
        fi
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
    phase3-plan|plan3) phase3_plan ;;
    phase3|3) phase3 ;;
    all)
        phase1
        echo ""
        phase2
        echo ""
        phase3
        ;;
    *)
        echo "Usage: $0 [phase1|phase2|phase3-plan|phase3|all]"
        echo ""
        echo "  phase1  - Test Proxmox API connectivity"
        echo "  phase2  - Build Packer template (runs phase1 first)"
        echo "  phase3-plan - Terraform dry-run plan only"
        echo "  phase3  - Deploy VMs with Terraform + Ansible"
        echo "  all     - Run all phases in sequence"
        exit 1
        ;;
esac
