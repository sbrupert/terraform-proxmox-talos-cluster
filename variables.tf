variable "cluster" {
  description = "Talos cluster identity and high-level behavior. The Kubernetes API endpoint is derived from api_vip or the first control-plane management IP unless endpoint_url is set."

  type = object({
    name                           = string
    api_vip                        = optional(string)
    endpoint_url                   = optional(string)
    allow_control_plane_scheduling = optional(bool, false)
  })

  validation {
    condition     = try(var.cluster.endpoint_url, null) == null ? true : startswith(var.cluster.endpoint_url, "https://")
    error_message = "cluster.endpoint_url must start with https:// when set."
  }

  validation {
    condition     = try(var.cluster.api_vip, null) == null ? true : can(cidrhost("${var.cluster.api_vip}/32", 0))
    error_message = "cluster.api_vip must be a valid IPv4 address when set."
  }

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.cluster.name)) && length(var.cluster.name) <= 63
    error_message = "cluster.name must be a lowercase DNS label of at most 63 characters."
  }
}

variable "versions" {
  description = "Talos, Kubernetes, Cilium, and Gateway API bootstrap software versions/settings."

  type = object({
    kubernetes = string

    talos = object({
      version = string
    })

    cilium = optional(object({
      version = optional(string, "1.18.0")
      values  = optional(any, {})
    }), {})

    gateway_api = optional(object({
      version          = optional(string, "v1.4.1")
      install_tlsroute = optional(bool, true)
    }), {})
  })
}

variable "proxmox" {
  description = "Existing Proxmox import image file ID, storage, snippets, guest-agent policy, and role-level VM profile settings."

  type = object({
    image_file_id = string

    datastores = object({
      vm_disks = string
      snippets = string
    })

    guest_agent = optional(object({
      enabled = optional(bool, true)
    }), {})

    vm_profiles = object({
      controlplane = object({
        cpu_cores    = number
        memory_mb    = number
        disk_size_gb = number
      })

      worker = optional(object({
        cpu_cores    = number
        memory_mb    = number
        disk_size_gb = number
      }))
    })
  })

  validation {
    condition = alltrue([
      var.proxmox.vm_profiles.controlplane.cpu_cores > 0,
      var.proxmox.vm_profiles.controlplane.memory_mb >= 1024,
      var.proxmox.vm_profiles.controlplane.disk_size_gb > 0,
      var.proxmox.vm_profiles.worker == null ? true : var.proxmox.vm_profiles.worker.cpu_cores > 0,
      var.proxmox.vm_profiles.worker == null ? true : var.proxmox.vm_profiles.worker.memory_mb >= 1024,
      var.proxmox.vm_profiles.worker == null ? true : var.proxmox.vm_profiles.worker.disk_size_gb > 0,
    ])

    error_message = "Each proxmox.vm_profiles role must use cpu_cores > 0, memory_mb >= 1024, and disk_size_gb > 0."
  }

  validation {
    condition     = can(regex("^[^:]+:import/.+", var.proxmox.image_file_id))
    error_message = "proxmox.image_file_id must be an existing bpg/proxmox import file ID in <datastore>:import/<filename> form."
  }

  validation {
    condition     = length(var.nodes.worker) == 0 || var.proxmox.vm_profiles.worker != null
    error_message = "proxmox.vm_profiles.worker is required when nodes.worker is non-empty."
  }
}

variable "networks" {
  description = "Flat map of logical VM networks keyed by network name. The reserved management network is NIC0 and the only network allowed to define gateway/DNS."

  type = map(object({
    bridge           = string
    cidr             = string
    gateway          = optional(string)
    dns_servers      = optional(list(string), [])
    proxmox_firewall = optional(bool, false)
  }))

  validation {
    condition     = contains(keys(var.networks), "management")
    error_message = "networks must include a reserved management network."
  }

  validation {
    condition = alltrue([
      for name, network in var.networks : can(cidrhost(network.cidr, 0))
    ])

    error_message = "Each network.cidr must be valid CIDR notation."
  }

  validation {
    condition = alltrue([
      for name, network in var.networks : name == "management" || try(network.gateway, null) == null
    ])

    error_message = "Only networks.management may define gateway/default route settings."
  }

  validation {
    condition = alltrue([
      for name, network in var.networks : name == "management" || length(try(network.dns_servers, [])) == 0
    ])

    error_message = "Only networks.management may define dns_servers."
  }
}

variable "nodes" {
  description = "Talos nodes grouped by role and keyed by desired hostname. Node network maps reference top-level networks by name and provide the node IP for each network."

  type = object({
    controlplane = map(object({
      host_node = string
      vm_id     = optional(number)
      networks  = map(string)
    }))

    worker = optional(map(object({
      host_node = string
      vm_id     = optional(number)
      networks  = map(string)
    })), {})
  })

  validation {
    condition     = length(var.nodes.controlplane) > 0
    error_message = "At least one controlplane node is required."
  }

  validation {
    condition = alltrue([
      for name in concat(keys(var.nodes.controlplane), keys(var.nodes.worker)) :
      length(name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", name))
    ])
    error_message = "Every node name must be a lowercase DNS label of at most 63 characters."
  }

  validation {
    condition = alltrue(concat(
      [for _, node in var.nodes.controlplane : contains(keys(node.networks), "management")],
      [for _, node in var.nodes.worker : contains(keys(node.networks), "management")],
    ))

    error_message = "Every node must define networks.management."
  }

  validation {
    condition = alltrue(flatten(concat(
      [for _, node in var.nodes.controlplane : [for _, ip in node.networks : can(cidrhost("${ip}/32", 0))]],
      [for _, node in var.nodes.worker : [for _, ip in node.networks : can(cidrhost("${ip}/32", 0))]],
    )))

    error_message = "Every node network value must be a valid IPv4 address."
  }
}

variable "bootstrap" {
  description = "Whether to run Talos configuration apply, one-time cluster bootstrap, and kubeconfig retrieval. Set false to create and inspect nodes first."
  type        = bool
  default     = true
}
