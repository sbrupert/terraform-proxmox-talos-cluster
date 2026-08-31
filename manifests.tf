locals {
  cilium_config      = var.versions.cilium
  gateway_api_config = var.versions.gateway_api

  cilium_base_values = {
    ipam = {
      mode = "kubernetes"
    }

    kubeProxyReplacement = true
    k8sServiceHost       = "localhost"
    k8sServicePort       = 7445

    securityContext = {
      capabilities = {
        ciliumAgent = [
          "CHOWN",
          "KILL",
          "NET_ADMIN",
          "NET_RAW",
          "IPC_LOCK",
          "SYS_ADMIN",
          "SYS_RESOURCE",
          "DAC_OVERRIDE",
          "FOWNER",
          "SETGID",
          "SETUID",
        ]

        cleanCiliumState = [
          "NET_ADMIN",
          "SYS_ADMIN",
          "SYS_RESOURCE",
        ]
      }
    }

    cgroup = {
      autoMount = {
        enabled = false
      }
      hostRoot = "/sys/fs/cgroup"
    }

    gatewayAPI = {
      enabled           = true
      enableAlpn        = true
      enableAppProtocol = true

      gatewayClass = {
        # Helm renders offline here, so API discovery cannot enable this for us.
        create = "true"
      }
    }

    hubble = {
      tls = {
        auto = {
          method = "cronJob"
        }
      }
      relay = {
        enabled = true
      }
    }
  }

  cilium_values = merge(local.cilium_base_values, local.cilium_config.values)

  cilium_kube_version = trimprefix(var.versions.kubernetes, "v")

  gateway_api_crd_base_url = "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${local.gateway_api_config.version}/config/crd"

  gateway_api_standard_crds = [
    "gatewayclasses",
    "gateways",
    "httproutes",
    "referencegrants",
    "grpcroutes",
  ]

  gateway_api_standard_manifest_urls = [
    for crd in local.gateway_api_standard_crds :
    "${local.gateway_api_crd_base_url}/standard/gateway.networking.k8s.io_${crd}.yaml"
  ]

  gateway_api_experimental_manifest_urls = local.gateway_api_config.install_tlsroute ? [
    "${local.gateway_api_crd_base_url}/experimental/gateway.networking.k8s.io_tlsroutes.yaml",
  ] : []

  kubelet_serving_cert_approver_manifest_url = "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/v0.12.0/deploy/standalone-install.yaml"
  metrics_server_manifest_url                = "https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml"

  control_plane_extra_manifests = concat(
    local.gateway_api_standard_manifest_urls,
    local.gateway_api_experimental_manifest_urls,
    [
      local.kubelet_serving_cert_approver_manifest_url,
      local.metrics_server_manifest_url,
    ],
  )
}

data "helm_template" "cilium" {
  name         = "cilium"
  namespace    = "kube-system"
  repository   = "https://helm.cilium.io/"
  chart        = "cilium"
  version      = local.cilium_config.version
  kube_version = local.cilium_kube_version

  values = [
    yamlencode(local.cilium_values)
  ]
}
