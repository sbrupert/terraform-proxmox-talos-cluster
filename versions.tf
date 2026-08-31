terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.103.0"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
  }
}
