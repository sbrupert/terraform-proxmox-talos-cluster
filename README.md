# Terraform Proxmox Talos Cluster

An opinionated OpenTofu/Terraform module for creating and bootstrapping Talos Linux Kubernetes clusters on Proxmox VE.

The module turns an explicit cluster inventory—software versions, Proxmox placement, VM profiles, networks, and node addresses—into Proxmox virtual machines, Talos machine configuration, Kubernetes bootstrap resources, and usable Talos and Kubernetes client credentials.

> [!WARNING]
> **Early development:** this module has not reached a stable `1.0` contract. Inputs, outputs, defaults, generated configuration, resource addresses, and lifecycle behavior may change as real cluster creation and recovery scenarios are tested. Pin an exact release or commit, review every plan, and expect migrations between early versions.

## Intended use

This module is intended for operators who want to:

- Run Talos Linux Kubernetes clusters as Proxmox VMs.
- Describe control-plane and worker nodes with explicit Proxmox placement and static network addresses.
- Generate deterministic NoCloud and Talos machine configuration from one typed contract.
- Bootstrap Cilium, Gateway API CRDs, Metrics Server, and kubelet serving-certificate support as part of the initial cluster lifecycle.
- Apply Talos configuration, bootstrap etcd, wait for cluster health, and retrieve kubeconfig through OpenTofu.

The module favors an explicit, relationship-oriented contract over automatic allocation. The caller defines software versions and role-level VM profiles once, defines named networks once, and then lists each node with its Proxmox host and per-network IP addresses.

## Current scope

The module manages:

1. Talos cluster secrets and client configuration.
2. Per-node Talos machine configuration.
3. NoCloud user-data, metadata, and network snippets in Proxmox.
4. Proxmox virtual machines for control-plane and worker nodes.
5. Talos machine-configuration application.
6. One-time Talos bootstrap and cluster health checks.
7. Kubernetes kubeconfig retrieval.
8. Bootstrap-critical Kubernetes manifests rendered into the Talos control-plane configuration.

The module deliberately does **not** manage:

- Talos Image Factory resolution or Proxmox image downloads.
- IP address, VM ID, or Proxmox placement allocation.
- DNS, DHCP, firewall, or load-balancer configuration outside the VMs.
- Talos or Kubernetes rolling upgrades.
- Downstream platform add-ons beyond the bootstrap-critical manifests.
- Cluster backups, disaster recovery, or application workloads.

These boundaries keep each cluster state independent and prevent cluster destruction from deleting a shared Talos image used by other clusters.

## Requirements and assumptions

Before using the module, the caller must provide:

- A reachable Proxmox VE environment and appropriately scoped provider credentials.
- SSH access to each selected Proxmox node. The module uploads snippet content, which requires SSH in the pinned `bpg/proxmox` provider.
- An existing Talos `nocloud` import image. Pass its native Proxmox file ID as `proxmox.image_file_id` using `<datastore>:import/<filename>` form.
- VM disk and snippet datastores available to the selected Proxmox nodes.
- Preallocated node addresses and, when used, a Kubernetes API VIP.
- Network bridges that already exist on the selected Proxmox hosts.
- Network reachability from the OpenTofu runner to the Proxmox API, Proxmox SSH endpoints, Talos API endpoints, and Kubernetes API endpoint.

Provider configuration belongs to the calling root configuration. This module declares provider requirements but does not configure credentials or endpoints.

## Supported private-cloud Talos image profile

This module currently targets private or local Proxmox cloud environments where iSCSI and NFS are common shared-storage protocols. It assumes the caller-owned Talos NoCloud image is built to support iSCSI, NFS, and the QEMU guest agent.

Use a Talos Image Factory schematic that includes these official system extensions:

```yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/qemu-guest-agent
      - siderolabs/iscsi-tools
      - siderolabs/nfs-utils
```

The schematic's Talos version, platform, and architecture must match the image referenced by `proxmox.image_file_id`. The module does not build or own this image, install a CSI driver, or provision external storage; it prepares Talos nodes for storage integrations that use these common private-cloud protocols.

QEMU guest-agent support is enabled by default through `proxmox.guest_agent.enabled`. The module asks Proxmox to wait for guest-agent IP reporting, so an image without a running QEMU guest agent can cause VM creation or refresh operations to wait or time out. The supported profile assumes every Proxmox VM includes the guest agent as an operational best practice. Callers may deliberately set `guest_agent.enabled = false`, but that is outside the preferred profile.

The iSCSI, NFS, and QEMU guest-agent assumptions may become caller-selectable in a future module contract. For now they are part of the opinionated platform profile rather than optional features.

## Cluster contract

The primary inputs are:

| Input | Responsibility |
| --- | --- |
| `cluster` | Cluster identity, API endpoint/VIP, and control-plane scheduling behavior |
| `versions` | Kubernetes, Talos, Cilium, and Gateway API versions/settings |
| `proxmox` | Existing image ID, datastores, guest-agent policy, and role-level VM profiles |
| `networks` | Named network definitions, including the required management network |
| `nodes` | Control-plane and worker membership, Proxmox placement, optional VM IDs, and addresses |
| `bootstrap` | Whether to apply Talos configuration, bootstrap the cluster, wait for health, and retrieve kubeconfig |

Important network rules:

- `networks.management` is required and always becomes NIC0.
- Every node must have an address on the management network.
- Only the management network may define the default gateway and DNS servers.
- Additional networks become NIC1+ in deterministic key order.
- etcd advertised subnets and kubelet valid node-IP subnets derive from the management CIDR.

Setting `bootstrap = false` creates the snippets and VMs but stops before live Talos configuration application. This is useful for inspecting generated configuration and first-boot behavior.

## Image ownership

The Talos image is an environment-level dependency, not a cluster-owned resource. Create or manage it outside this module and pass the resulting ID directly:

```hcl
resource "proxmox_download_file" "talos" {
  node_name    = "pve01"
  content_type = "import"
  datastore_id = "shared-images"
  overwrite    = false

  url       = "https://factory.talos.dev/image/<schematic-id>/v1.13.5/nocloud-amd64.raw"
  file_name = "talos-v1.13.5-nocloud-amd64.raw"
}

module "cluster" {
  source = "git::https://github.com/sbrupert/terraform-proxmox-talos-cluster.git?ref=<release-or-commit>"

  # Other required inputs omitted.
  proxmox = {
    image_file_id = proxmox_download_file.talos.id

    datastores = {
      vm_disks = "vm-disks"
      snippets = "snippets"
    }

    vm_profiles = {
      controlplane = {
        cpu_cores    = 4
        memory_mb    = 8192
        disk_size_gb = 64
      }
    }
  }
}
```

Changing `proxmox.image_file_id` does not upgrade existing nodes. The Proxmox import source is used during initial disk creation; Talos upgrades require a separate, health-gated operational workflow.

## Minimal example

The following example describes one workload-capable control-plane node. Use addresses, bridges, storage, image IDs, and placement appropriate for your environment.

```hcl
module "cluster" {
  source = "git::https://github.com/sbrupert/terraform-proxmox-talos-cluster.git?ref=<release-or-commit>"

  cluster = {
    name                           = "talos-dev"
    api_vip                        = "192.0.2.10"
    allow_control_plane_scheduling = true
  }

  versions = {
    kubernetes = "v1.36.2"

    talos = {
      version = "v1.13.5"
    }

    cilium = {
      version = "1.19.5"
    }

    gateway_api = {
      version          = "v1.4.1"
      install_tlsroute = true
    }
  }

  proxmox = {
    image_file_id = "shared-images:import/talos-v1.13.5-nocloud-amd64.raw"

    datastores = {
      vm_disks = "vm-disks"
      snippets = "snippets"
    }

    vm_profiles = {
      controlplane = {
        cpu_cores    = 4
        memory_mb    = 8192
        disk_size_gb = 64
      }
    }
  }

  networks = {
    management = {
      bridge      = "vmbr0"
      cidr        = "192.0.2.0/24"
      gateway     = "192.0.2.1"
      dns_servers = ["192.0.2.1"]
    }
  }

  nodes = {
    controlplane = {
      cp01 = {
        host_node = "pve01"
        vm_id     = 2001
        networks = {
          management = "192.0.2.11"
        }
      }
    }
  }
}
```

See the complete examples:

- [`examples/control-plane-only`](examples/control-plane-only)
- [`examples/control-plane-workers`](examples/control-plane-workers)

## Lifecycle and safety

This module creates and can destroy complete Kubernetes clusters. Treat plans and state as sensitive operational artifacts:

- Pin the module to an exact release or commit.
- Keep state encrypted and backed up.
- Protect generated Talos configuration, talosconfig, and kubeconfig.
- Review replacement and destruction actions before applying.
- Back up Talos etcd and persistent storage independently.
- Do not assume deleting and recreating state will safely adopt surviving VMs or clusters.
- Test creation, interruption, reconciliation, and deletion with disposable clusters before using the module for important workloads.

Until the module reaches `1.0`, release notes should be treated as required migration documentation rather than optional reading.

## Development

Run the repository validation workflow with:

```sh
./scripts/validate.sh
```

The validation script formats and validates the root module, runs the module tests, validates both examples, checks generated documentation when `terraform-docs` is available, and checks the Git diff for whitespace errors.

The detailed module reference below is generated with `terraform-docs`:

```sh
terraform-docs .
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0, < 2.0.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | 3.2.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 0.103.0 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | 0.11.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 3.2.0 |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 0.103.0 |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.11.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [proxmox_virtual_environment_file.nocloud_meta_data](https://registry.terraform.io/providers/bpg/proxmox/0.103.0/docs/resources/virtual_environment_file) | resource |
| [proxmox_virtual_environment_file.nocloud_network_config](https://registry.terraform.io/providers/bpg/proxmox/0.103.0/docs/resources/virtual_environment_file) | resource |
| [proxmox_virtual_environment_file.nocloud_user_data](https://registry.terraform.io/providers/bpg/proxmox/0.103.0/docs/resources/virtual_environment_file) | resource |
| [proxmox_virtual_environment_vm.node](https://registry.terraform.io/providers/bpg/proxmox/0.103.0/docs/resources/virtual_environment_vm) | resource |
| [talos_cluster_kubeconfig.this](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/cluster_kubeconfig) | resource |
| [talos_machine_bootstrap.this](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/machine_bootstrap) | resource |
| [talos_machine_configuration_apply.node](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/machine_configuration_apply) | resource |
| [talos_machine_secrets.this](https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/machine_secrets) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bootstrap"></a> [bootstrap](#input\_bootstrap) | Whether to run Talos configuration apply, one-time cluster bootstrap, and kubeconfig retrieval. Set false to create and inspect nodes first. | `bool` | `true` | no |
| <a name="input_cluster"></a> [cluster](#input\_cluster) | Talos cluster identity and high-level behavior. The Kubernetes API endpoint is derived from api\_vip or the first control-plane management IP unless endpoint\_url is set. | <pre>object({<br/>    name                           = string<br/>    api_vip                        = optional(string)<br/>    endpoint_url                   = optional(string)<br/>    allow_control_plane_scheduling = optional(bool, false)<br/>  })</pre> | n/a | yes |
| <a name="input_networks"></a> [networks](#input\_networks) | Flat map of logical VM networks keyed by network name. The reserved management network is NIC0 and the only network allowed to define gateway/DNS. | <pre>map(object({<br/>    bridge           = string<br/>    cidr             = string<br/>    gateway          = optional(string)<br/>    dns_servers      = optional(list(string), [])<br/>    proxmox_firewall = optional(bool, false)<br/>  }))</pre> | n/a | yes |
| <a name="input_nodes"></a> [nodes](#input\_nodes) | Talos nodes grouped by role and keyed by desired hostname. Node network maps reference top-level networks by name and provide the node IP for each network. | <pre>object({<br/>    controlplane = map(object({<br/>      host_node = string<br/>      vm_id     = optional(number)<br/>      networks  = map(string)<br/>    }))<br/><br/>    worker = optional(map(object({<br/>      host_node = string<br/>      vm_id     = optional(number)<br/>      networks  = map(string)<br/>    })), {})<br/>  })</pre> | n/a | yes |
| <a name="input_proxmox"></a> [proxmox](#input\_proxmox) | Existing Proxmox import image file ID, storage, snippets, guest-agent policy, and role-level VM profile settings. | <pre>object({<br/>    image_file_id = string<br/><br/>    datastores = object({<br/>      vm_disks = string<br/>      snippets = string<br/>    })<br/><br/>    guest_agent = optional(object({<br/>      enabled = optional(bool, true)<br/>    }), {})<br/><br/>    vm_profiles = object({<br/>      controlplane = object({<br/>        cpu_cores    = number<br/>        memory_mb    = number<br/>        disk_size_gb = number<br/>      })<br/><br/>      worker = optional(object({<br/>        cpu_cores    = number<br/>        memory_mb    = number<br/>        disk_size_gb = number<br/>      }))<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_versions"></a> [versions](#input\_versions) | Talos, Kubernetes, Cilium, and Gateway API bootstrap software versions/settings. | <pre>object({<br/>    kubernetes = string<br/><br/>    talos = object({<br/>      version = string<br/>    })<br/><br/>    cilium = optional(object({<br/>      version = optional(string, "1.18.0")<br/>      values  = optional(any, {})<br/>    }), {})<br/><br/>    gateway_api = optional(object({<br/>      version          = optional(string, "v1.4.1")<br/>      install_tlsroute = optional(bool, true)<br/>    }), {})<br/>  })</pre> | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_identity"></a> [cluster\_identity](#output\_cluster\_identity) | Stable cluster identity metadata. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Kubernetes API endpoint for the cluster. |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Generated Kubernetes kubeconfig after Talos bootstrap. Null when bootstrap is false. |
| <a name="output_talosconfig"></a> [talosconfig](#output\_talosconfig) | Generated talosctl client configuration. |
<!-- END_TF_DOCS -->
