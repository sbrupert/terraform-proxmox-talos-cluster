check "no_duplicate_node_names" {
  assert {
    condition     = length(local.duplicate_node_names) == 0
    error_message = "Node names must be unique across nodes.controlplane and nodes.worker. Duplicate names: ${join(", ", local.duplicate_node_names)}."
  }
}

check "worker_vm_profile_required" {
  assert {
    condition     = length(var.nodes.worker) == 0 || var.proxmox.vm_profiles.worker != null
    error_message = "proxmox.vm_profiles.worker is required when nodes.worker is non-empty."
  }
}

check "node_network_keys_exist" {
  assert {
    condition     = length(local.invalid_node_network_key_messages) == 0
    error_message = "Invalid node network references: ${join("; ", local.invalid_node_network_key_messages)}."
  }
}

check "node_network_ips_match_cidrs" {
  assert {
    condition     = length(local.invalid_node_network_cidr_messages) == 0
    error_message = "Invalid node network IPs: ${join("; ", local.invalid_node_network_cidr_messages)}."
  }
}

check "node_network_interfaces_are_unique" {
  assert {
    condition     = length(local.invalid_duplicate_node_interface_messages) == 0
    error_message = "Invalid normalized NIC interfaces: ${join("; ", local.invalid_duplicate_node_interface_messages)}."
  }
}

check "api_vip_is_management_ip" {
  assert {
    condition     = length(local.invalid_cluster_api_vip_messages) == 0
    error_message = join("; ", local.invalid_cluster_api_vip_messages)
  }
}

check "management_ips_are_unique" {
  assert {
    condition     = length(distinct(local.management_ips)) == length(local.management_ips)
    error_message = "Every node management IP must be unique."
  }
}

check "explicit_vm_ids_are_unique" {
  assert {
    condition     = length(distinct(local.explicit_vm_ids)) == length(local.explicit_vm_ids)
    error_message = "Every explicitly assigned VM ID must be unique."
  }
}

check "api_vip_does_not_match_node" {
  assert {
    condition     = try(var.cluster.api_vip, null) == null || !contains(local.management_ips, var.cluster.api_vip)
    error_message = "cluster.api_vip must not equal a node management IP."
  }
}
