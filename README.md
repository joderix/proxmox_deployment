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
│  Proxmox 8.4 Cluster (192.168.3.23 - direct IP, not via reverse proxy) │
│                                                          │
│  Templates: Fedora COSMIC Atomic + Ubuntu Server        │
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
cp .env.fedora.example .env.fedora
cp .env.ubuntu.example .env.ubuntu
# Edit .env, .env.fedora, and .env.ubuntu with your actual Proxmox API token and SSH key
```

### 2. Build and start the dev container

```bash
docker compose build
docker compose run --rm deployer bash
```

The container includes:

- **Packer** v1.15.1 — VM template builder
- **Terraform** v1.14.8 — Infrastructure provisioning
- **Ansible** v2.18.12 — Configuration management
- **Python** v3.14.3 — Proxmox API client (`proxmoxer`)

The entrypoint automatically:

- Initializes git repository (if needed)
- Exports Packer and Terraform environment variables from `.env`
- Displays installed tool versions

### 3. Run the deployment pipeline

#### Option A: Modern Web Dashboard (Recommended) ⭐

A beautiful, modern web-based dashboard that works on Windows, macOS, and Linux:

```bash
# Windows (PowerShell)
pwsh launch-web.ps1

# Windows (Command Prompt)
launch-web.bat

# macOS / Linux
bash launch-web.sh

# Or run directly with Python
python app.py
```

Then open your browser to: **http://localhost:5000**

**Features:**

- 🎨 Modern, responsive UI with dark theme
- 🖱️ One-click buttons for each phase
- 📊 Real-time live logs with color-coded output
- ⏹️ Cancel button to stop long-running tasks
- 🌐 Works on any OS with a web browser
- 💻 Clean, professional dashboard
- 📱 Mobile-responsive design

**Buttons:**

- 🧭 **Profile selector** — Choose `Fedora COSMIC Atomic` or `Ubuntu Server`
- 🏗️ **Build Container** — Create Docker image
- 🧪 **Phase 1: Test API** — Verify Proxmox connectivity (~5 sec)
- 📦 **Phase 2: Build Template** — Packer template creation (15-30 min)
- 🧾 **Phase 3: Plan Only** — Terraform dry-run only (no apply)
- 🚀 **Phase 3: Deploy VMs** — Terraform VM deployment (2-5 min)
- 🛑 **Cancel** — Stop any running task
- 🗑️ **Clear Logs** — Clear the log viewer

Template/profile auto-mapping is enabled in the web UI:

- `9104` -> `fedora`
- `9204` -> `ubuntu`

When you enter a mapped template ID, the profile is auto-selected.
You can update these defaults in [config/template_profile_map.json](config/template_profile_map.json).

#### Option B: Command line

Use one-line commands below for PowerShell. (Backslash `\` line continuation is Bash-only.)

Quick copy (minimum commands):

```bash
# Fedora (template 9104)
docker compose --env-file .env.fedora --project-directory . run --rm --service-ports -e PROJECT_PROFILE=fedora -e PKR_VAR_template_vm_id=9104 deployer ./scripts/deploy.sh phase2

docker compose --env-file .env.fedora --project-directory . run --rm -e PROJECT_PROFILE=fedora -e TF_VAR_template_vm_id=9104 -e TF_VAR_vm_count=1 deployer ./scripts/deploy.sh phase3
```

```bash
# Ubuntu (template 9204)
docker compose --env-file .env.ubuntu --project-directory . run --rm -e PROJECT_PROFILE=ubuntu -e PKR_VAR_base_cloud_image_vm_id=9002 -e PKR_VAR_template_vm_id=9204 deployer ./scripts/deploy.sh phase2

docker compose --env-file .env.ubuntu --project-directory . run --rm -e PROJECT_PROFILE=ubuntu -e TF_VAR_template_vm_id=9204 -e TF_VAR_vm_count=1 deployer ./scripts/deploy.sh phase3
```

Full step-by-step workflows:

```bash
# Build image once (shared by both profiles)
docker compose build

# ================================================================
# FEDORA WORKFLOW (template VMID 9104)
# Uses: .env.fedora
# NOTE: Phase 2 requires --service-ports for kickstart HTTP
# ================================================================

# Phase 1: API test
docker compose --env-file .env.fedora --project-directory . run --rm -e PROJECT_PROFILE=fedora deployer ./scripts/deploy.sh phase1

# Phase 2: Build Fedora template
docker compose --env-file .env.fedora --project-directory . run --rm --service-ports -e PROJECT_PROFILE=fedora -e PKR_VAR_template_vm_id=9104 deployer ./scripts/deploy.sh phase2

# Phase 3 plan: Dry-run Fedora VM deployment
docker compose --env-file .env.fedora --project-directory . run --rm -e PROJECT_PROFILE=fedora -e TF_VAR_template_vm_id=9104 -e TF_VAR_vm_count=1 deployer ./scripts/deploy.sh phase3-plan

# Phase 3 deploy: Deploy Fedora VMs
docker compose --env-file .env.fedora --project-directory . run --rm -e PROJECT_PROFILE=fedora -e TF_VAR_template_vm_id=9104 -e TF_VAR_vm_count=1 deployer ./scripts/deploy.sh phase3

# ================================================================
# UBUNTU WORKFLOW (template VMID 9204)
# Uses: .env.ubuntu
# NOTE: Phase 2 does NOT need --service-ports (cloud-image clone)
# NOTE: PKR_VAR_base_cloud_image_vm_id must be the existing imported
#       Ubuntu cloud-image base template VMID in Proxmox.
# ================================================================

# Phase 1: API test
docker compose --env-file .env.ubuntu --project-directory . run --rm -e PROJECT_PROFILE=ubuntu deployer ./scripts/deploy.sh phase1

# Phase 2: Build Ubuntu template
docker compose --env-file .env.ubuntu --project-directory . run --rm -e PROJECT_PROFILE=ubuntu -e PKR_VAR_base_cloud_image_vm_id=9002 -e PKR_VAR_template_vm_id=9204 deployer ./scripts/deploy.sh phase2

# Phase 3 plan: Dry-run Ubuntu VM deployment
docker compose --env-file .env.ubuntu --project-directory . run --rm -e PROJECT_PROFILE=ubuntu -e TF_VAR_template_vm_id=9204 -e TF_VAR_vm_count=1 deployer ./scripts/deploy.sh phase3-plan

# Phase 3 deploy: Deploy Ubuntu VMs
docker compose --env-file .env.ubuntu --project-directory . run --rm -e PROJECT_PROFILE=ubuntu -e TF_VAR_template_vm_id=9204 -e TF_VAR_vm_count=1 deployer ./scripts/deploy.sh phase3
```

## Testing

PowerShell test scripts are in the [`test/`](test/) directory:

| Script | Purpose |
|--------|---------|
| `test/build.ps1` | Build Docker image with no cache |
| `test/test.ps1` | Test container startup and entrypoint |
| `test/check.ps1` | Verify `/entrypoint.sh` exists in container |
| `test/rebuild.ps1` | Rebuild image and display last 30 lines |
| `test/final_test.ps1` | Full smoke test (startup + environment) |
| `test/network-diagnostics.ps1` | Network connectivity debugging |

Run from workspace root:

```powershell
pwsh test/build.ps1
pwsh test/final_test.ps1
```

## Project Structure

```
proxmox-deployment/
├── .dockerignore           # Docker build context exclusions
├── .env                    # Credentials (git-ignored)
├── .env.example            # Credential template
├── .env.fedora.example     # Fedora profile environment template
├── .env.ubuntu.example     # Ubuntu profile environment template
├── .gitignore              # Git ignore rules
├── Dockerfile              # Dev container with all tools
├── README.md
├── app.py                  # Flask web server for dashboard
├── config/
│   └── template_profile_map.json  # Template ID -> profile mapping for web auto-selection
├── docker-compose.yml      # Container orchestration
├── entrypoint.sh           # Auto-setup git + env vars + HTTP server IP detection
├── launch-web.bat          # Web dashboard launcher for Windows Command Prompt
├── launch-web.ps1          # Web dashboard launcher for Windows PowerShell
├── launch-web.py           # Python launcher for web dashboard
├── launch-web.sh           # Web dashboard launcher for macOS / Linux
├── requirements-web.txt    # Python dependencies for web dashboard
├── ansible/
│   ├── ansible.cfg         # Ansible configuration
│   └── playbook.yml        # Fedora post-deployment configuration
├── ansible-ubuntu/
│   ├── ansible.cfg         # Ubuntu Ansible configuration
│   └── playbook.yml        # Ubuntu post-deployment configuration
├── packer/
│   ├── fedora-cosmic-atomic.pkr.hcl  # Phase 2: Template builder
│   ├── variables.pkr.hcl             # Packer variables
│   └── http/
│       └── ks.cfg                     # Kickstart for automated install
├── packer-ubuntu/
│   ├── ubuntu-server.pkr.hcl         # Ubuntu template builder (cloud-image clone)
│   ├── variables.pkr.hcl             # Ubuntu Packer variables
│   └── (clones imported Ubuntu cloud image base template)
├── scripts/
│   ├── deploy.sh           # Master deployment script
│   └── test_proxmox_api.py # Phase 1: API connectivity test
├── templates/
│   └── index.html          # Modern web dashboard UI (embedded CSS/JS)
├── terraform/
│   ├── inventory.tftpl     # Ansible inventory template
│   ├── main.tf             # VM resources + Ansible integration
│   ├── outputs.tf          # Deployment outputs
│   ├── providers.tf        # Proxmox provider (bpg/proxmox)
│   └── variables.tf        # Configurable parameters
├── terraform-ubuntu/
│   ├── inventory.tftpl     # Ubuntu Ansible inventory template
│   ├── main.tf             # Ubuntu VM resources + Ansible integration
│   ├── outputs.tf          # Ubuntu deployment outputs
│   ├── providers.tf        # Proxmox provider (bpg/proxmox)
│   └── variables.tf        # Ubuntu configurable parameters
└── test/
    ├── build.ps1           # Build Docker image with no cache
    ├── check.ps1           # Verify /entrypoint.sh exists in container
    ├── final_test.ps1      # Full smoke test (startup + environment)
    ├── network-diagnostics.ps1  # Network connectivity debugging
    ├── rebuild.ps1         # Rebuild image and display last 30 lines
    └── test.ps1            # Test container startup and entrypoint
```

## Phase Details

### Phase 1 — API Connectivity Test

Tests Proxmox API accessibility, token permissions, storage access, and ISO availability.

Phase 1 does not use or resolve template IDs.

### Phase 2 — Packer Template Build

Creates a Proxmox VM template from the selected profile:

- **Fedora profile**: `packer/` with kickstart (`os_fedora-cosmic-atomic`)
- **Ubuntu profile**: `packer-ubuntu/` with cloud-image clone (`os_ubuntu`)

Fedora default hardware:

- **CPU**: 4 cores, `x86-64-v2-AES` (optimal for AMD↔Intel live migration)
- **Memory**: 4 GB
- **Disk**: 32 GB on local-lvm (VirtIO SCSI Single)
- **BIOS**: UEFI (OVMF)
- **Display**: VirtIO-GPU via Spice (copy-paste support)
- **Cloud-Init**: Pre-configured with NoCloud datasource
- **QEMU Guest Agent**: Enabled

### Phase 3 — Terraform VM Deployment

Deploys VMs by cloning the template from the selected profile (`terraform/` or `terraform-ubuntu/`):

- **Naming**: `srv-test-01`, `srv-test-02`, ... (configurable count)
- **CPU**: 2 cores
- **Memory**: 6 GB
- **Disk**: 64 GB
- **IPs**: `192.168.3.201`, `192.168.3.202`, ... (static, derived from hostname)
- **Cloud-Init**: User `ansible`, DNS `local.derix.icu`, package upgrade enabled

After deployment, Ansible automatically installs extra packages via `rpm-ostree`.

For Ubuntu profile, post-deployment packages are installed via `apt`.

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
- Fedora ISO `Fedora-COSMIC-Atomic-ostree-x86_64-43-1.6.iso` uploaded to `local` storage on Proxmox
- Ubuntu image `noble-server-cloud-amd64.img` uploaded to `local` storage on Proxmox
- Ubuntu base cloud-image template VM imported in Proxmox (set `PKR_VAR_base_cloud_image_vm_id` in `.env.ubuntu`)
- Valid Proxmox API token with VM creation permissions

## Notes

- The kickstart `ostreesetup` ref (`fedora/43/x86_64/cosmic-atomic`) may need adjustment depending on the exact ISO variant. Check the ISO's `/ostree/repo` for the correct ref.
- Fedora Atomic uses `rpm-ostree` for package management. Layered packages require a reboot to apply.
- The `.env` file contains secrets and is excluded from git via `.gitignore`.

## Troubleshooting

### Phase 3 (Terraform + Ansible) — callback plugin error `community.general.yaml`

**Symptom**:

```
The 'community.general.yaml' callback plugin has been removed
```

**Cause**: Newer Ansible versions removed that callback plugin from `community.general`.

**Fix**: In `ansible/ansible.cfg` and `ansible-ubuntu/ansible.cfg`, use:

```ini
stdout_callback = default
```

### Phase 2 (Packer / Fedora profile) — HTTP Server Not Reachable from Proxmox VMs

**Symptom**: Packer starts building but times out during kickstart with error like:
```
curl: (7) Failed to connect to 192.168.3.113 port 18080
```

**Cause**: `docker compose run` does not publish service ports unless `--service-ports` is passed. Without published ports, Proxmox can see the URL but your host has no listener.

This applies to the Fedora profile (kickstart over HTTP). Ubuntu profile uses cloud-image clone and does not require kickstart HTTP serving.

**Solution**:

Use a fixed published port and run Phase 2 with service ports enabled.

1. **Set your host IP in** `docker-compose.yml`:

   ```yaml
   services:
     deployer:
       environment:
         PKR_VAR_http_server_ip: "192.168.3.113"   # your reachable host IP
               PKR_VAR_http_server_port: "18080"
       ports:
               - "18080:18080"
   ```

2. **Run Phase 2 with published ports**:

   ```powershell
   docker compose run --rm --service-ports deployer ./scripts/deploy.sh phase2
   ```

3. **Check the host is listening while Phase 2 is running**:

   ```powershell
   netstat -ano | findstr :18080
   ```

4. **If still unreachable, allow inbound firewall on TCP 18080** from your LAN.

**To verify values inside the container**:

```bash
docker compose run --rm deployer bash
# Then inside container:
echo $PKR_VAR_http_server_ip
echo $PKR_VAR_http_server_port
```
