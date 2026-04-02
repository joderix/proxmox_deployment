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
    # Use a SCSI cloud-init device; this template was not detecting IDE cloud-init media in-guest.
    interface = "scsi1"

    # User configuration
    user_account {
      username = var.ci_user
      password = var.ci_password
      keys     = compact([var.ssh_public_key, var.ssh_public_key_secondary])
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

    # # Upgrade packages on first boot
    # upgrade = true
  }

  # Wait for the VM to be fully started before marking as created
  started = true

}

# ── Generate Ansible Inventory ────────────────────────────────────
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    vms = [for i, vm in proxmox_virtual_environment_vm.srv_test : {
      name = vm.name
      # Keep inventory aligned with the cloud-init static address plan.
      ip   = format("192.168.3.%d", var.ip_base_octet + i + 1)
    }]
    ansible_user            = var.ci_user
    ansible_password        = var.ci_password
    ansible_become_password = var.ci_password
  })
  filename = "${path.module}/../ansible-ubuntu/inventory.yml"

  depends_on = [proxmox_virtual_environment_vm.srv_test]
}

# ── Run Ansible after deployment ──────────────────────────────────
resource "null_resource" "ansible_provisioning" {
  # Re-run when any VM changes
  triggers = {
    vm_ids = join(",", [for vm in proxmox_virtual_environment_vm.srv_test : vm.id])
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../ansible-ubuntu"
    environment = {
      ANSIBLE_CONFIG            = "${path.module}/../ansible-ubuntu/ansible.cfg"
      ANSIBLE_HOST_KEY_CHECKING = "False"
    }
    command = join("\n", [
      "echo 'Waiting for VMs to boot (Ansible will wait for SSH)...'",
      "sleep 10",
      "ansible-playbook -i inventory.yml playbook.yml"
    ])
  }

  depends_on = [local_file.ansible_inventory]
}
