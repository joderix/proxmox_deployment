# ── Packer Configuration ──────────────────────────────────────────
packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ── Proxmox Cloud Image Clone Source ──────────────────────────────
source "proxmox-clone" "ubuntu-server" {
  # Connection
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # Clone from a pre-imported Ubuntu cloud image template
  clone_vm_id = var.base_cloud_image_vm_id
  full_clone  = true

  # VMID for the generated Ubuntu template artifact
  vm_id = var.template_vm_id

  # Template
  template_name        = var.template_name
  template_description = "Ubuntu Server 24.04 LTS - Cloud-init enabled [os=ubuntu]"
  tags                 = "os_ubuntu"

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

  # SSH connection for provisioners (Ubuntu cloud images default to ubuntu user)
  ssh_username = var.ssh_username
  ssh_timeout  = var.ssh_timeout
}

# ── Build ──────────────────────────────────────────────────────────
build {
  sources = ["source.proxmox-clone.ubuntu-server"]

  # Ensure cloud-init and qemu-guest-agent are present and enabled.
  provisioner "shell" {
    inline = [
      "echo 'Installing cloud-init and qemu-guest-agent...'",
      "sudo apt-get update -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y cloud-init qemu-guest-agent",
      "sudo systemctl enable --now qemu-guest-agent || true",
      "sudo systemctl enable cloud-init cloud-config cloud-final cloud-init-local || true",
      "echo 'Preparing Ubuntu template cleanup...'",
      "sudo cloud-init clean --logs || true",
      "sudo rm -f /etc/machine-id",
      "sudo truncate -s 0 /etc/machine-id",
      "echo 'Template preparation complete!'"
    ]
  }
}
