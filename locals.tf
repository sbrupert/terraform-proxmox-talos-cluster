locals {
  management_network = var.networks.management
  management_prefix  = tonumber(split("/", local.management_network.cidr)[1])

  duplicate_node_names = setintersection(
    toset(keys(var.nodes.controlplane)),
    toset(keys(var.nodes.worker)),
  )

  raw_nodes = merge(
    {
      for name, node in var.nodes.controlplane : name => merge(node, {
        machine_type = "controlplane"
      })
    },
    {
      for name, node in var.nodes.worker : name => merge(node, {
        machine_type = "worker"
      })
    },
  )

  nodes = {
    for name, node in local.raw_nodes : name => {
      name          = name
      host_node     = node.host_node
      machine_type  = node.machine_type
      vm_id         = try(node.vm_id, null)
      management_ip = node.networks.management
      vm_profile = coalesce(
        try(var.proxmox.vm_profiles[node.machine_type], null),
        {
          cpu_cores    = 0
          memory_mb    = 0
          disk_size_gb = 0
        },
      )

      nics = [
        for idx, network_key in concat(
          ["management"],
          sort([
            for candidate_network_key in keys(node.networks) : candidate_network_key
            if candidate_network_key != "management" && contains(keys(var.networks), candidate_network_key)
          ]),
          ) : {
          key              = network_key
          interface        = "eth${idx}"
          bridge           = try(var.networks[network_key].bridge, null)
          ip               = node.networks[network_key]
          address          = try("${node.networks[network_key]}/${tonumber(split("/", var.networks[network_key].cidr)[1])}", null)
          netmask          = try(cidrnetmask(var.networks[network_key].cidr), null)
          gateway          = network_key == "management" ? try(var.networks[network_key].gateway, null) : null
          dns_servers      = network_key == "management" ? try(var.networks[network_key].dns_servers, []) : []
          proxmox_firewall = try(var.networks[network_key].proxmox_firewall, false)
        }
      ]
    }
  }

  invalid_node_network_key_messages = flatten([
    for node_name, node in local.raw_nodes : [
      for network_key in keys(node.networks) : "${node_name}.networks.${network_key} does not match any key in var.networks"
      if !contains(keys(var.networks), network_key)
    ]
  ])

  invalid_node_network_cidr_messages = flatten([
    for node_name, node in local.raw_nodes : [
      for network_key, ip in node.networks : "${node_name}.networks.${network_key} (${ip}) must be inside ${var.networks[network_key].cidr}"
      if contains(keys(var.networks), network_key) && !try(
        cidrhost(
          "${ip}/${split("/", var.networks[network_key].cidr)[1]}",
          0,
        ) == cidrhost(var.networks[network_key].cidr, 0),
        false,
      )
    ]
  ])

  invalid_duplicate_node_interface_messages = [
    for node_name, node in local.nodes : "${node_name} has duplicate normalized NIC interface names: ${join(", ", [for nic in node.nics : nic.interface])}"
    if length(distinct([for nic in node.nics : nic.interface])) != length(node.nics)
  ]

  invalid_cluster_api_vip_messages = try(var.cluster.api_vip, null) == null ? [] : (
    try(
      cidrhost(
        "${var.cluster.api_vip}/${local.management_prefix}",
        0,
      ) == cidrhost(local.management_network.cidr, 0),
      false,
    )
    ? []
    : ["cluster.api_vip (${var.cluster.api_vip}) must be inside networks.management.cidr (${local.management_network.cidr})."]
  )

  control_plane_nodes = {
    for name, node in local.nodes : name => node
    if node.machine_type == "controlplane"
  }

  worker_nodes = {
    for name, node in local.nodes : name => node
    if node.machine_type == "worker"
  }

  node_ips = [
    for _, node in local.nodes : node.management_ip
  ]

  control_plane_ips = [
    for _, node in local.control_plane_nodes : node.management_ip
  ]

  worker_ips = [
    for _, node in local.worker_nodes : node.management_ip
  ]

  first_control_plane_name = sort(keys(local.control_plane_nodes))[0]
  first_control_plane_ip   = local.control_plane_nodes[local.first_control_plane_name].management_ip

  cluster_endpoint_url = coalesce(
    try(var.cluster.endpoint_url, null),
    try(var.cluster.api_vip, null) != null ? "https://${var.cluster.api_vip}:6443" : "https://${local.first_control_plane_ip}:6443",
  )

  management_ips  = [for node in values(local.nodes) : node.management_ip]
  explicit_vm_ids = [for node in values(local.nodes) : node.vm_id if node.vm_id != null]
}
