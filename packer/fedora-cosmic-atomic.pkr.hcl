# ── Packer Configuration ──────────────────────────────────────────
packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ── Proxmox ISO Source ────────────────────────────────────────────
source "proxmox-iso" "fedora-cosmic-atomic" {
  # Connection
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # Template
  vm_id                = var.template_vm_id
  template_name        = var.template_name
  template_description = "Fedora COSMIC Atomic 43 - Cloud-init enabled [os=fedora-cosmic-atomic]"
  tags                 = "os_fedora-cosmic-atomic"

  # Boot ISO (replaces deprecated unmount_iso and iso_file)
  boot_iso {
    iso_file = var.iso_file
  }

  # ── Hardware ─────────────────────────────────────────────────────
  # CPU: x86-64-v2-AES is the best for live migration between AMD and Intel
  cores    = 4
  cpu_type = "x86-64-v2-AES"
  memory   = 4096
  os       = "l26"

  # UEFI BIOS with OVMF
  bios = "ovmf"
  efi_config {
    efi_storage_pool  = "local-lvm"
    efi_type          = "4m"
    pre_enrolled_keys = false
  }

  # VGA: VirtIO-GPU for Spice (copy-paste support in Proxmox console)
  vga {
    type = "virtio"
  }

  # SCSI controller: VirtIO SCSI Single
  scsi_controller = "virtio-scsi-single"

  # Disk: 32GB on local-lvm
  disks {
    disk_size    = "32G"
    storage_pool = "local-lvm"
    type         = "scsi"
    discard      = true
    ssd          = true
  }

  # Network
  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # QEMU Guest Agent
  qemu_agent = true

  # Cloud-Init drive
  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"

  # ── Kickstart via HTTP ───────────────────────────────────────────
  # http_directory: Location of kickstart files to serve via Packer's built-in HTTP server
  # http_server_ip: IP address for Proxmox VMs to reach the kickstart file
  # Must be set to your host machine's IP on the local network (e.g., 192.168.3.100)
  # Override with: export PKR_VAR_http_server_ip="192.168.3.100"
  http_directory    = "http"
  http_bind_address = "0.0.0.0"
  http_port_min     = var.http_server_port
  http_port_max     = var.http_server_port

  # Boot command for UEFI Fedora installer (GRUB)
  # Uses http_server_ip variable to specify reachable IP (instead of Packer's auto-detected {{ .HTTPIP }})
  boot_wait = "15s"
  boot_command = [
    "<up><wait5>",
    "e<wait3>",
    "<down><down><end>",
    " inst.ks=http://${var.http_server_ip}:${var.http_server_port}/ks.cfg",
    "<leftCtrlOn>x<leftCtrlOff>"
  ]

  # SSH connection for provisioners (matches kickstart user)
  ssh_username = "ansible"
  ssh_password = "simplylovely"
  ssh_timeout  = var.ssh_timeout
}

# ── Build ──────────────────────────────────────────────────────────
build {
  sources = ["source.proxmox-iso.fedora-cosmic-atomic"]

  # Provisioner 1: Install cloud-init, qemu-guest-agent, and optional tooling
  # via rpm-ostree. This reduces phase3 network dependency.
  provisioner "shell" {
    inline = [
      "echo 'Layering base and optional packages into template (best effort with retries)...'",
      "for attempt in 1 2 3 4; do",
      "  sudo rpm-ostree refresh-md || true",
      "  if sudo rpm-ostree install --idempotent --allow-inactive cloud-init qemu-guest-agent git vim curl wget jq python3 python3-pip htop tmux bash-completion; then",
      "    echo 'rpm-ostree package layering succeeded'",
      "    break",
      "  fi",
      "  if [ \"$attempt\" -eq 4 ]; then",
      "    echo 'WARNING: rpm-ostree package layering failed after retries; continuing template build'",
      "  else",
      "    echo \"rpm-ostree layering attempt $attempt failed; retrying in 30s...\"",
      "    sleep 30",
      "  fi",
      "done",
      "echo 'rpm-ostree status after install:'",
      "sudo rpm-ostree status",
      "echo 'Rebooting to apply rpm-ostree changes...'",
      "sudo systemctl reboot"
    ]
    expect_disconnect = true
  }

  # Provisioner 2: Enable services and clean up after reboot
  provisioner "shell" {
    pause_before = "30s"
    inline = [
      "echo 'Verifying rpm-ostree deployment...'",
      "rpm -q cloud-init qemu-guest-agent git vim curl wget jq python3 python3-pip htop tmux bash-completion || echo 'WARNING: some optional packages are not present in current deployment'",
      "",
      "echo 'Enabling qemu-guest-agent...'",
      "sudo systemctl enable --now qemu-guest-agent || true",
      "",
      "echo 'Enabling cloud-init services (if present)...'",
      "for svc in cloud-init-local cloud-init cloud-config cloud-final; do",
      "  if systemctl list-unit-files \"$svc.service\" | grep -q \"$svc\"; then",
      "    sudo systemctl enable \"$svc\"",
      "    echo \"  Enabled $svc\"",
      "  else",
      "    echo \"  Skipping $svc (not found)\"",
      "  fi",
      "done",
      "",
      "echo 'Configuring cloud-init datasource for Proxmox (NoCloud)...'",
      "sudo tee /etc/cloud/cloud.cfg.d/99-proxmox.cfg > /dev/null << 'CLOUDCFG'",
      "datasource_list: [NoCloud, ConfigDrive, None]",
      "CLOUDCFG",
      "",
      "echo 'Setting default cloud-init user configuration...'",
      "sudo tee /etc/cloud/cloud.cfg.d/50-defaults.cfg > /dev/null << 'CLOUDDEFAULTS'",
      "system_info:",
      "  default_user:",
      "    name: ansible",
      "    lock_passwd: false",
      "    sudo: ALL=(ALL) NOPASSWD:ALL",
      "    shell: /bin/bash",
      "package_upgrade: true",
      "CLOUDDEFAULTS",
      "",
      "echo 'Cleaning cloud-init state for template...'",
      "sudo cloud-init clean --logs --seed || sudo cloud-init clean --logs",
      "sudo rm -rf /var/lib/cloud/* || true",
      "sudo rm -f /etc/machine-id",
      "sudo truncate -s 0 /etc/machine-id",
      "",
      "echo 'Template preparation complete!'"
    ]
  }
}
