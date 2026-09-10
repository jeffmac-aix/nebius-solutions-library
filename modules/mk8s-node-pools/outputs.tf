output "pools" {
  description = "Pool IDs, actual vs requested hardware, and scheduling contract."
  value = { for key, pool in nebius_mk8s_v1_node_group.this : key => {
    id                 = pool.id
    name               = pool.name
    requested_platform = var.pools[key].platform
    actual_platform    = pool.template.resources.platform
    actual_preset      = pool.template.resources.preset
    simulated          = var.simulation.enabled
    node_selector      = { "nebius.com/pool" = key }
    node_labels        = local.node_labels[key]
    tolerations = [for t in var.pools[key].taints : {
      key      = t.key
      operator = "Equal"
      value    = t.value
      effect   = lookup({ NO_SCHEDULE = "NoSchedule", PREFER_NO_SCHEDULE = "PreferNoSchedule", NO_EXECUTE = "NoExecute" }, t.effect, t.effect)
    }]
  } }
}

output "gpu_clusters" {
  value = { for key, cluster in nebius_compute_v1_gpu_cluster.this : key => cluster.id }
}
