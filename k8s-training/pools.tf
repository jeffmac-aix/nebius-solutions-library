resource "terraform_data" "pool_configuration" {
  lifecycle {
    precondition {
      condition     = !var.pool_simulation.enabled || var.gpu_pools != null
      error_message = "CPU simulation requires gpu_pools; legacy GPU groups are never simulated."
    }
    precondition {
      condition     = var.gpu_pools == null || (var.mig_parted_config == null && (var.mig_strategy == null || var.mig_strategy == "none"))
      error_message = "Named pools currently support whole GPUs only. Remove global MIG settings."
    }
    precondition {
      condition     = var.gpu_pools == null || (!var.enable_gpu_kubelet_numa && var.gpu_kubelet_numa_config == null && var.gpu_kubelet_numa_preset == null)
      error_message = "Global GPU NUMA settings cannot be applied to heterogeneous pools. Leave them unset for named pools."
    }
    precondition {
      condition = var.gpu_pools == null || !var.test_mode || try(
        !var.pool_simulation.enabled &&
        local.named_gpu_pools[var.nccl_test_pool].platform == "gpu-h100-sxm" &&
        startswith(local.named_gpu_pools[var.nccl_test_pool].preset, "8gpu-") &&
        local.named_gpu_pools[var.nccl_test_pool].fixed_node_count > 0 &&
      (local.named_gpu_pools[var.nccl_test_pool].gpu_cluster_key != null || local.named_gpu_pools[var.nccl_test_pool].existing_gpu_cluster_id != null), false)
      error_message = "Named-pool test_mode requires nccl_test_pool selecting a real, fixed-size, eight-GPU H100 SXM pool with InfiniBand. The existing benchmark is hardware-specific."
    }
    precondition {
      condition     = var.gpu_pools == null || (!var.enable_kuberay_cluster && !var.enable_kuberay_service)
      error_message = "Bundled Ray workloads use the legacy global GPU platform. Disable them with named pools and deploy workloads using the gpu_pools output's selectors/tolerations."
    }
  }
}

module "gpu_pools" {
  source             = "../modules/mk8s-node-pools"
  parent_id          = var.parent_id
  cluster_id         = nebius_mk8s_v1_cluster.k8s-cluster.id
  cluster_name       = var.cluster_name
  subnet_id          = var.subnet_id
  k8s_version        = var.k8s_version
  service_account_id = var.enable_k8s_node_group_sa ? nebius_iam_v1_service_account.k8s_node_group_sa[0].id : null
  pools              = local.named_gpu_pools
  gpu_clusters       = var.gpu_pools == null ? {} : var.pool_gpu_clusters
  simulation         = var.pool_simulation
  drivers_preset     = var.gpu_nodes_driverfull_image ? local.device_preset : null
  filesystems = local.shared-filesystem == null ? [] : [{
    attach_mode         = "READ_WRITE"
    mount_tag           = local.filestore.mount_tag
    existing_filesystem = { id = local.shared-filesystem.id }
  }]
  cloud_init = { for key, pool in local.named_gpu_pools : key => templatefile("${path.module}/../modules/cloud-init/k8s-cloud-init.tftpl", {
    enable_filestore         = var.enable_filestore && pool.attach_filesystems ? "true" : "false"
    filestore_mount_path     = local.filestore.mount_path
    ssh_user_name            = var.ssh_user_name
    ssh_public_key           = local.ssh_public_key
    kubelet_numa_config      = null
    kubelet_numa_config_yaml = ""
  }) }
  depends_on = [terraform_data.pool_configuration]
}
