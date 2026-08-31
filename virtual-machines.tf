resource "proxmox_virtual_environment_file" "nocloud_user_data" {
  for_each = local.nodes

  content_type = "snippets"
  datastore_id = var.proxmox.datastores.snippets
  node_name    = each.value.host_node
  overwrite    = true

  source_raw {
    data      = sensitive(data.talos_machine_configuration.this[each.key].machine_configuration)
    file_name = "${var.cluster.name}-${each.key}-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_file" "nocloud_meta_data" {
  for_each = local.nodes

  content_type = "snippets"
  datastore_id = var.proxmox.datastores.snippets
  node_name    = each.value.host_node
  overwrite    = true

  source_raw {
    data      = "instance-id: ${each.key}\n"
    file_name = "${var.cluster.name}-${each.key}-meta-data.yaml"
  }
}

resource "proxmox_virtual_environment_file" "nocloud_network_config" {
  for_each = local.nodes

  content_type = "snippets"
  datastore_id = var.proxmox.datastores.snippets
  node_name    = each.value.host_node
  overwrite    = true

  source_raw {
    data = templatefile("${path.module}/nocloud/network-config.yaml.tftpl", {
      nics = each.value.nics
    })
    file_name = "${var.cluster.name}-${each.key}-network-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes

  name      = each.key
  node_name = each.value.host_node
  vm_id     = each.value.vm_id

  description = "Talos ${each.value.machine_type} node for ${var.cluster.name}"
  tags        = ["talos", var.cluster.name, each.value.machine_type]

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"

  started = true
  on_boot = true

  stop_on_destroy = true

  agent {
    enabled = var.proxmox.guest_agent.enabled
    trim    = var.proxmox.guest_agent.enabled

    dynamic "wait_for_ip" {
      for_each = var.proxmox.guest_agent.enabled ? [true] : []

      content {
        ipv4 = true
      }
    }
  }

  cpu {
    cores = each.value.vm_profile.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = each.value.vm_profile.memory_mb
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.proxmox.datastores.vm_disks
    size         = each.value.vm_profile.disk_size_gb
    import_from  = var.proxmox.image_file_id
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  dynamic "network_device" {
    for_each = each.value.nics

    content {
      bridge   = network_device.value.bridge
      model    = "virtio"
      firewall = network_device.value.proxmox_firewall
    }
  }

  initialization {
    datastore_id = var.proxmox.datastores.vm_disks

    user_data_file_id    = proxmox_virtual_environment_file.nocloud_user_data[each.key].id
    meta_data_file_id    = proxmox_virtual_environment_file.nocloud_meta_data[each.key].id
    network_data_file_id = proxmox_virtual_environment_file.nocloud_network_config[each.key].id
  }

  operating_system {
    type = "l26"
  }

  vga {
    type = "std"
  }

  # Talos configuration apply is the live update channel. Keep the VM attached
  # to its stable user-data filename when the snippet contents are refreshed.
  lifecycle {
    ignore_changes = [
      initialization[0].user_data_file_id,
    ]
  }
}
