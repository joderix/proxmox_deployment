# ── Phase 3: Proxmox VM Deployment ────────────────────────────────
# Deploys VMs by cloning the Packer-created template.
# VM naming: srv-test-01, srv-test-02, ... (dynamic count)
# IP scheme: 192.168.3.2XX where XX = VM number (01→201, 02→202, etc.)

resource "proxmox_virtual_environment_vm" "srv_test" {
  count     = var.vm_count
  name      = format("%s-%02d", var.vm_name_prefix, count.index + 1)
  node_name = var.proxmox_node

  # Clone from the Packer-created template
  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  # CPU: 2 cores, x86-64-v2-AES for AMD/Intel migration compatibility
  cpu {
    cores = var.vm_cpu_cores
    type  = "x86-64-v2-AES"
  }

  # Memory: 6GB
  memory {
    dedicated = var.vm_memory_mb
  }

  # Disk: 64GB on local-lvm (resized from template's 32GB)
  disk {
    interface    = "scsi0"
    size         = var.vm_disk_size_gb
    datastore_id = "local-lvm"
    discard      = "on"
    ssd          = true
  }

  # VGA: VirtIO-GPU for Spice
  vga {
    type = "virtio"
  }

  # Network
  network_device {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # QEMU Guest Agent
  agent {
    enabled = true
  }

  # ── Cloud-Init Configuration ─────────────────────────────────────
  initialization {
    # User configuration
    user_account {
      username = var.ci_user
      password = var.ci_password
      keys     = [var.ssh_public_key]
    }

    # DNS
    dns {
      domain  = var.dns_domain
      servers = var.dns_servers
    }

    # Static IP: 192.168.3.2XX where XX is the VM number
    ip_config {
      ipv4 {
        address = format("192.168.3.%d%s", var.ip_base_octet + count.index + 1, var.network_subnet)
        gateway = var.network_gateway
      }
    }

    # Upgrade packages on first boot
    upgrade = true
  }

  # Wait for the VM to be fully started before marking as created
  started = true

  lifecycle {
    ignore_changes = [
      # Ignore changes to cloud-init after initial deployment
      initialization,
    ]
  }
}

# ── Generate Ansible Inventory ────────────────────────────────────
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    vms = [for i, vm in proxmox_virtual_environment_vm.srv_test : {
      name = vm.name
      ip   = format("192.168.3.%d", var.ip_base_octet + i + 1)
    }]
    ansible_user = var.ci_user
  })
  filename = "${path.module}/../ansible/inventory.yml"

  depends_on = [proxmox_virtual_environment_vm.srv_test]
}

# ── Run Ansible after deployment ──────────────────────────────────
resource "null_resource" "ansible_provisioning" {
  # Re-run when any VM changes
  triggers = {
    vm_ids = join(",", [for vm in proxmox_virtual_environment_vm.srv_test : vm.id])
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../ansible"
    command     = <<-EOT
      echo "Waiting 60s for VMs to finish cloud-init..."
      sleep 60
      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i inventory.yml \
        playbook.yml
    EOT
  }

  depends_on = [local_file.ansible_inventory]
}
