output "kubeconfig" {
  description = "Generated Kubernetes kubeconfig after Talos bootstrap. Null when bootstrap is false."
  value       = try(talos_cluster_kubeconfig.this[0].kubeconfig_raw, null)
  sensitive   = true
}

output "talosconfig" {
  description = "Generated talosctl client configuration."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "endpoint" {
  description = "Kubernetes API endpoint for the cluster."
  value       = local.cluster_endpoint_url
}

output "cluster_identity" {
  description = "Stable cluster identity metadata."
  value = {
    name = var.cluster.name
  }
}
