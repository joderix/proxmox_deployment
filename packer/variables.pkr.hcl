# ── Proxmox Connection ────────────────────────────────────────────
variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL (e.g., https://pve03.local.derix.icu:8006/api2/json)"
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
  default = "fedora-cosmic-atomic-template"
}

variable "iso_file" {
  type    = string
  default = "local:iso/Fedora-COSMIC-Atomic-ostree-x86_64-43-1.6.iso"
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "SSH public key for cloud-init"
}
