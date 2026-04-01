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
  template_name        = var.template_name
  template_description = "Fedora COSMIC Atomic 43 - Cloud-init enabled"
  unmount_iso          = true

  # ISO
  iso_file = var.iso_file

  # ── Hardware ─────────────────────────────────────────────────────
  # CPU: x86-64-v2-AES is the best for live migration between AMD and Intel
  cores    = 2
  cpu_type = "x86-64-v2-AES"
  memory   = 2048
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
  http_directory = "http"

  # Boot command for UEFI Fedora installer (GRUB)
  # Navigates GRUB menu, appends kickstart URL to kernel parameters
  boot_wait = "15s"
  boot_command = [
    "<up><wait5>",
    "e<wait3>",
    "<down><down><end>",
    " inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    "<leftCtrlOn>x<leftCtrlOff>"
  ]

  # SSH connection for provisioners (matches kickstart user)
  ssh_username = "ansible"
  ssh_password = "simplylovely"
  ssh_timeout  = "30m"
}

# ── Build ──────────────────────────────────────────────────────────
build {
  sources = ["source.proxmox-iso.fedora-cosmic-atomic"]

  # Provisioner 1: Install cloud-init and qemu-guest-agent via rpm-ostree
  # (Fedora Atomic uses rpm-ostree for package layering)
  provisioner "shell" {
    inline = [
      "echo 'Installing cloud-init and qemu-guest-agent...'",
      "sudo rpm-ostree install cloud-init qemu-guest-agent",
      "echo 'Rebooting to apply rpm-ostree changes...'",
      "sudo systemctl reboot"
    ]
    expect_disconnect = true
  }

  # Provisioner 2: Enable services and clean up after reboot
  provisioner "shell" {
    pause_before = "30s"
    inline = [
      "echo 'Enabling services...'",
      "sudo systemctl enable --now qemu-guest-agent",
      "sudo systemctl enable cloud-init cloud-init-local cloud-config cloud-final",
      "",
      "echo 'Configuring cloud-init datasource for Proxmox (NoCloud)...'",
      "sudo tee /etc/cloud/cloud.cfg.d/99-proxmox.cfg > /dev/null << 'CLOUDCFG'",
      "datasource_list: [NoCloud, ConfigDrive, None]",
      "datasource:",
      "  NoCloud:",
      "    meta-data:",
      "      instance-id: iid-local01",
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
      "sudo cloud-init clean --logs",
      "sudo rm -f /etc/machine-id",
      "sudo truncate -s 0 /etc/machine-id",
      "",
      "echo 'Template preparation complete!'"
    ]
  }
}
