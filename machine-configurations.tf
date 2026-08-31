resource "talos_machine_secrets" "this" {
  talos_version = var.versions.talos.version
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = local.node_ips
  endpoints            = local.control_plane_ips
}

data "talos_machine_configuration" "this" {
  for_each = local.nodes

  cluster_name       = var.cluster.name
  cluster_endpoint   = local.cluster_endpoint_url
  talos_version      = var.versions.talos.version
  kubernetes_version = var.versions.kubernetes
  machine_type       = each.value.machine_type
  machine_secrets    = talos_machine_secrets.this.machine_secrets

  config_patches = concat(
    [
      templatefile(
        "${path.module}/machine-config/node.yaml.tftpl",
        {
          hostname          = each.key
          nics              = each.value.nics
          management_subnet = local.management_network.cidr
          dns_servers       = each.value.nics[0].dns_servers
          layer2_vip = each.value.machine_type == "controlplane" && try(var.cluster.api_vip, null) != null ? {
            ip        = var.cluster.api_vip
            interface = each.value.nics[0].interface
          } : null
        }
      )
    ],
    each.value.machine_type == "controlplane" ? [
      sensitive(templatefile(
        "${path.module}/machine-config/control-plane-bootstrap.yaml.tftpl",
        {
          allow_control_plane_scheduling = var.cluster.allow_control_plane_scheduling
          extra_manifests                = local.control_plane_extra_manifests
          cilium_manifest                = data.helm_template.cilium.manifest
        }
      ))
    ] : []
  )
}
