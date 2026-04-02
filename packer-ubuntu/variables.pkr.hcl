# ── Proxmox Connection ────────────────────────────────────────────
variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL (use IP address, e.g., https://192.168.3.23:8006/api2/json; avoid hostnames that resolve to reverse proxies)"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API token ID (e.g., root@pam!ansible)"
}

variable "proxmox_api_token_secret" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret"
}

variable "proxmox_node" {
  type        = string
  default     = "pve03"
  description = "Proxmox node name to build on"
}

# ── Template Settings ─────────────────────────────────────────────
variable "template_name" {
  type    = string
  default = "ubuntu-server-template"
}

variable "template_vm_id" {
  type        = number
  default     = 9204
  description = "VMID for the final Ubuntu template built by Packer."
}

variable "base_cloud_image_file" {
  type        = string
  default     = "local:iso/noble-server-cloud-amd64.img"
  description = "Reference filename of the imported Ubuntu cloud image artifact in Proxmox storage. Used for documentation/audit; cloning uses base_cloud_image_vm_id."
}

variable "base_cloud_image_vm_id" {
  type        = number
  default     = 9002
  description = "VMID of pre-imported Ubuntu cloud-image base template to clone (created from base_cloud_image_file). Override via PKR_VAR_base_cloud_image_vm_id with your actual Proxmox VMID."
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "SSH public key for cloud-init"
}

variable "ssh_username" {
  type        = string
  default     = "ubuntu"
  description = "Default SSH user for the Ubuntu cloud image during provisioning."
}

variable "ssh_timeout" {
  type        = string
  default     = "90m"
  description = "Maximum wait time for SSH during first boot and post-reboot provisioning. Increase on slow storage/hosts."
}
