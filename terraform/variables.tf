# ── Proxmox Connection ────────────────────────────────────────────
variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API token ID"
}

variable "proxmox_api_token_secret" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret"
}

variable "proxmox_node" {
  type        = string
  default     = "pve03"
  description = "Proxmox node to deploy VMs on"
}

# ── VM Configuration ──────────────────────────────────────────────
variable "vm_count" {
  type        = number
  default     = 1
  description = "Number of VMs to deploy (e.g., 3 creates srv-test-01, srv-test-02, srv-test-03)"
}

variable "vm_name_prefix" {
  type        = string
  default     = "srv-test"
  description = "Prefix for VM names (followed by -01, -02, etc.)"
}

variable "template_vm_id" {
  type        = number
  description = "VM ID of the Packer-created template to clone from"
}

variable "vm_cpu_cores" {
  type    = number
  default = 2
}

variable "vm_memory_mb" {
  type    = number
  default = 6144
  description = "VM memory in MB (6GB = 6144)"
}

variable "vm_disk_size_gb" {
  type    = number
  default = 64
  description = "VM disk size in GB"
}

# ── Network ───────────────────────────────────────────────────────
variable "network_gateway" {
  type    = string
  default = "192.168.3.1"
}

variable "network_subnet" {
  type    = string
  default = "/24"
}

variable "ip_base_octet" {
  type        = number
  default     = 200
  description = "Base for the last IP octet. Final octet = base + VM number (e.g., 200+1=201)"
}

# ── Cloud-Init ────────────────────────────────────────────────────
variable "ci_user" {
  type    = string
  default = "ansible"
}

variable "ci_password" {
  type      = string
  default   = "simplylovely"
  sensitive = true
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for cloud-init"
}

variable "ssh_public_key_secondary" {
  type        = string
  default     = ""
  description = "Optional secondary SSH public key for cloud-init"
}

variable "dns_domain" {
  type    = string
  default = "local.derix.icu"
}

variable "dns_servers" {
  type    = list(string)
  default = ["192.168.3.53", "192.168.3.54"]
}
