# ── Terraform Configuration ────────────────────────────────────────
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
  }
}

# ── Proxmox Provider ──────────────────────────────────────────────
provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent = false
  }
}
