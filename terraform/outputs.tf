# ── Outputs ────────────────────────────────────────────────────────
output "vm_names" {
  description = "Names of deployed VMs"
  value       = [for vm in proxmox_virtual_environment_vm.srv_test : vm.name]
}

output "vm_ips" {
  description = "Static IP addresses of deployed VMs"
  value = [for i in range(var.vm_count) :
    format("192.168.3.%d", var.ip_base_octet + i + 1)
  ]
}

output "vm_details" {
  description = "VM name to IP mapping"
  value = { for i, vm in proxmox_virtual_environment_vm.srv_test :
    vm.name => format("192.168.3.%d", var.ip_base_octet + i + 1)
  }
}

output "ssh_command" {
  description = "SSH commands to connect to deployed VMs"
  value = [for i in range(var.vm_count) :
    format("ssh %s@192.168.3.%d", var.ci_user, var.ip_base_octet + i + 1)
  ]
}
