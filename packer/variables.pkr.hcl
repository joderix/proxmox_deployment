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
  default = "fedora-cosmic-atomic-template"
}

variable "template_vm_id" {
  type        = number
  default     = 9104
  description = "VMID for the final Fedora template built by Packer."
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

variable "ssh_timeout" {
  type        = string
  default     = "90m"
  description = "Maximum wait time for SSH during first boot and post-reboot provisioning. Increase on slow storage/hosts."
}

variable "http_server_ip" {
  type        = string
  default     = "localhost"
  description = "IP address of HTTP server serving kickstart file. Must be reachable from Proxmox VMs. Set PKR_VAR_http_server_ip=YOUR_HOST_IP (e.g., 192.168.3.100)"
}

variable "http_server_port" {
  type        = number
  default     = 18080
  description = "TCP port exposed by Docker for Packer HTTP server. Must match docker-compose port mapping."
}
