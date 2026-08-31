resource "talos_machine_configuration_apply" "node" {
  for_each = var.bootstrap ? local.nodes : {}

  node     = each.value.management_ip
  endpoint = each.value.management_ip

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  apply_mode                  = "auto"

  depends_on = [
    proxmox_virtual_environment_vm.node,
  ]
}

resource "talos_machine_bootstrap" "this" {
  count = var.bootstrap ? 1 : 0

  node     = local.first_control_plane_ip
  endpoint = local.first_control_plane_ip

  client_configuration = talos_machine_secrets.this.client_configuration

  depends_on = [
    talos_machine_configuration_apply.node,
  ]
}

data "talos_cluster_health" "this" {
  count = var.bootstrap ? 1 : 0

  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = local.control_plane_ips
  worker_nodes         = local.worker_ips
  endpoints            = local.control_plane_ips

  depends_on = [
    talos_machine_bootstrap.this,
  ]
}

resource "talos_cluster_kubeconfig" "this" {
  count = var.bootstrap ? 1 : 0

  node     = local.first_control_plane_ip
  endpoint = local.first_control_plane_ip

  client_configuration = talos_machine_secrets.this.client_configuration

  depends_on = [
    data.talos_cluster_health.this,
  ]
}
