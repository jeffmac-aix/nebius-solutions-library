locals {
  node_labels = { for key, pool in var.pools : key => merge(pool.node_labels, {
    "nebius.com/pool"               = key
    "nebius.com/simulated"          = tostring(var.simulation.enabled)
    "nebius.com/requested-platform" = pool.platform
  }) }
}

resource "nebius_compute_v1_gpu_cluster" "this" {
  for_each          = var.simulation.enabled ? {} : var.gpu_clusters
  parent_id         = var.parent_id
  name              = coalesce(each.value.name, "${var.cluster_name}-${each.key}")
  infiniband_fabric = each.value.infiniband_fabric
}

resource "nebius_mk8s_v1_node_group" "this" {
  for_each         = var.pools
  parent_id        = var.cluster_id
  name             = coalesce(each.value.name, "${var.cluster_name}-${each.key}")
  version          = var.k8s_version
  fixed_node_count = each.value.fixed_node_count
  autoscaling      = each.value.autoscaling
  labels           = { "library-solution" = "k8s-training" }

  template = {
    metadata = { labels = local.node_labels[each.key] }
    taints   = each.value.taints
    resources = {
      platform = var.simulation.enabled ? var.simulation.platform : each.value.platform
      preset   = var.simulation.enabled ? var.simulation.preset : each.value.preset
    }
    boot_disk = {
      type           = var.simulation.enabled ? "NETWORK_SSD" : each.value.disk_type
      size_gibibytes = var.simulation.enabled ? var.simulation.disk_size_gib : each.value.disk_size_gib
    }
    network_interfaces = [{
      subnet_id         = var.subnet_id
      public_ip_address = each.value.public_ips ? {} : null
    }]
    service_account_id = var.service_account_id
    preemptible = !var.simulation.enabled && each.value.preemptible ? {
      on_preemption = "STOP"
      priority      = 3
    } : null
    gpu_cluster = var.simulation.enabled ? null : (
      each.value.gpu_cluster_key != null ? { id = nebius_compute_v1_gpu_cluster.this[each.value.gpu_cluster_key].id } : (
        each.value.existing_gpu_cluster_id != null ? { id = each.value.existing_gpu_cluster_id } : null
      )
    )
    gpu_settings         = !var.simulation.enabled && var.drivers_preset != null ? { drivers_preset = var.drivers_preset } : null
    filesystems          = each.value.attach_filesystems && length(var.filesystems) > 0 ? var.filesystems : null
    underlay_required    = false
    cloud_init_user_data = lookup(var.cloud_init, each.key, null)
  }
}
