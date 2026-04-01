# Proxmox VM Deployment Platform

Automated VM deployment platform for Proxmox 8.4 cluster using infrastructure-as-code.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Docker Dev Container                                    │
│  (Packer + Terraform + Ansible + Python3)               │
│                                                          │
│  Phase 1 ──► Test Proxmox API connectivity              │
│  Phase 2 ──► Packer builds VM template with cloud-init  │
│  Phase 3 ──► Terraform deploys VMs + Ansible configures │
└─────────────┬───────────────────────────────────────────┘
              │ API
              ▼
┌─────────────────────────────────────────────────────────┐
│  Proxmox 8.4 Cluster (pve03.local.derix.icu)           │
│                                                          │
│  Template: Fedora COSMIC Atomic 43 (UEFI + Cloud-Init) │
│  VMs: srv-test-01 (192.168.3.201)                       │
│       srv-test-02 (192.168.3.202)                       │
│       srv-test-03 (192.168.3.203)                       │
│       ...                                                │
└─────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Configure credentials
```bash
cp .env.example .env
# Edit .env with your actual Proxmox API token and SSH key
```

### 2. Build and start the dev container
```bash
docker compose build
docker compose run --rm deployer bash
```

### 3. Run the deployment pipeline
```bash
# Inside the container:

# Test API connectivity only
./scripts/deploy.sh phase1

# Build Packer template (also runs phase1)
./scripts/deploy.sh phase2

# Deploy VMs with Terraform (interactive - asks for template ID and VM count)
./scripts/deploy.sh phase3

# Or run everything in sequence
./scripts/deploy.sh all
```

## Project Structure

```
proxmox-deployment/
├── Dockerfile              # Dev container with all tools
├── docker-compose.yml      # Container orchestration
├── entrypoint.sh           # Auto-setup git + env vars
├── .env                    # Credentials (git-ignored)
├── .env.example            # Credential template
├── scripts/
│   ├── test_proxmox_api.py # Phase 1: API connectivity test
│   └── deploy.sh           # Master deployment script
├── packer/
│   ├── fedora-cosmic-atomic.pkr.hcl  # Phase 2: Template builder
│   ├── variables.pkr.hcl             # Packer variables
│   └── http/
│       └── ks.cfg                     # Kickstart for automated install
├── terraform/
│   ├── providers.tf        # Phase 3: Proxmox provider (bpg/proxmox)
│   ├── main.tf             # VM resources + Ansible integration
│   ├── variables.tf        # Configurable parameters
│   ├── outputs.tf          # Deployment outputs
│   └── inventory.tftpl     # Ansible inventory template
├── ansible/
│   ├── ansible.cfg         # Ansible configuration
│   └── playbook.yml        # Post-deployment package installation
└── README.md
```

## Phase Details

### Phase 1 — API Connectivity Test
Tests Proxmox API accessibility, token permissions, storage access, and ISO availability.

### Phase 2 — Packer Template Build
Creates a Proxmox VM template from Fedora COSMIC Atomic 43 ISO with:
- **CPU**: 2 cores, `x86-64-v2-AES` (optimal for AMD↔Intel live migration)
- **Memory**: 2 GB
- **Disk**: 32 GB on local-lvm (VirtIO SCSI Single)
- **BIOS**: UEFI (OVMF)
- **Display**: VirtIO-GPU via Spice (copy-paste support)
- **Cloud-Init**: Pre-configured with NoCloud datasource
- **QEMU Guest Agent**: Enabled

### Phase 3 — Terraform VM Deployment
Deploys VMs by cloning the template:
- **Naming**: `srv-test-01`, `srv-test-02`, ... (configurable count)
- **CPU**: 2 cores
- **Memory**: 6 GB
- **Disk**: 64 GB
- **IPs**: `192.168.3.201`, `192.168.3.202`, ... (static, derived from hostname)
- **Cloud-Init**: User `ansible`, DNS `local.derix.icu`, package upgrade enabled

After deployment, Ansible automatically installs extra packages via `rpm-ostree`.

## Cloud-Init Parameters
| Parameter        | Value                                    |
|------------------|------------------------------------------|
| User             | ansible                                  |
| DNS Domain       | local.derix.icu                          |
| DNS Servers      | 192.168.3.53, 192.168.3.54              |
| IP Config        | Static (192.168.3.2XX)                   |
| Package Upgrade  | Yes                                      |

## Prerequisites
- Docker and Docker Compose installed on your workstation
- Proxmox 8.4 cluster accessible via API
- ISO `Fedora-COSMIC-Atomic-ostree-x86_64-43-1.6.iso` uploaded to `local` storage on Proxmox
- Valid Proxmox API token with VM creation permissions

## Notes
- The kickstart `ostreesetup` ref (`fedora/43/x86_64/cosmic-atomic`) may need adjustment depending on the exact ISO variant. Check the ISO's `/ostree/repo` for the correct ref.
- Fedora Atomic uses `rpm-ostree` for package management. Layered packages require a reboot to apply.
- The `.env` file contains secrets and is excluded from git via `.gitignore`.
