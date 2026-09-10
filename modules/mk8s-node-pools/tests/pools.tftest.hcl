mock_provider "nebius" {}

variables {
  parent_id    = "project-test"
  cluster_id   = "mk8s-test"
  cluster_name = "pool-test"
  subnet_id    = "subnet-test"
  gpu_clusters = { training = { infiniband_fabric = "fabric-test" } }
  pools = {
    training = {
      platform         = "gpu-h200-sxm"
      preset           = "8gpu-128vcpu-1600gb"
      fixed_node_count = 2
      gpu_cluster_key  = "training"
    }
    inference = {
      platform    = "gpu-h100-sxm"
      preset      = "1gpu-16vcpu-200gb"
      autoscaling = { min_node_count = 0, max_node_count = 3 }
    }
  }
}

run "heterogeneous_hardware" {
  command = plan
  assert {
    condition = (
      nebius_mk8s_v1_node_group.this["training"].template.resources.platform == "gpu-h200-sxm" &&
      nebius_mk8s_v1_node_group.this["inference"].template.resources.platform == "gpu-h100-sxm" &&
      nebius_mk8s_v1_node_group.this["training"].fixed_node_count == 2 &&
      nebius_mk8s_v1_node_group.this["inference"].fixed_node_count == null &&
      nebius_mk8s_v1_node_group.this["inference"].autoscaling.max_node_count == 3
    )
    error_message = "Hardware and scaling must remain independent per named pool."
  }
  assert {
    condition     = length(nebius_compute_v1_gpu_cluster.this) == 1 && nebius_mk8s_v1_node_group.this["inference"].template.gpu_cluster == null
    error_message = "Only the training placement domain should be created."
  }
}

run "cpu_simulation" {
  command = plan
  variables { simulation = { enabled = true } }
  assert {
    condition = alltrue([for p in nebius_mk8s_v1_node_group.this :
      p.template.resources.platform == "cpu-d3" &&
      p.template.resources.preset == "4vcpu-16gb" &&
      p.template.boot_disk.size_gibibytes == 64 &&
      p.template.gpu_settings == null && p.template.gpu_cluster == null && p.template.preemptible == null
    ]) && length(nebius_compute_v1_gpu_cluster.this) == 0
    error_message = "Simulation must never provision GPU hardware, drivers, InfiniBand, or preemptible CPU nodes."
  }
  assert {
    condition = (
      output.pools["training"].node_selector["nebius.com/pool"] == "training" &&
      output.pools["training"].node_labels["nebius.com/simulated"] == "true" &&
      output.pools["training"].requested_platform == "gpu-h200-sxm" &&
      output.pools["training"].tolerations[0].effect == "NoSchedule" &&
      nebius_mk8s_v1_node_group.this["training"].template.taints[0].effect == "NO_SCHEDULE"
    )
    error_message = "Simulation must retain the real scheduling contract and identify simulated nodes."
  }
}

run "conflicting_scaling" {
  command = plan
  variables {
    pools = { bad = {
      platform    = "gpu-h200-sxm", preset = "8gpu-128vcpu-1600gb", fixed_node_count = 1
      autoscaling = { min_node_count = 0, max_node_count = 2 }
    } }
  }
  expect_failures = [var.pools]
}

run "missing_scaling" {
  command = plan
  variables { pools = { bad = { platform = "gpu-h200-sxm", preset = "8gpu-128vcpu-1600gb" } } }
  expect_failures = [var.pools]
}

run "invalid_bounds" {
  command = plan
  variables {
    pools = { bad = {
      platform    = "gpu-h200-sxm", preset = "8gpu-128vcpu-1600gb"
      autoscaling = { min_node_count = 3, max_node_count = 2 }
    } }
  }
  expect_failures = [var.pools]
}

run "invalid_fabric_reference" {
  command = plan
  variables {
    simulation = { enabled = true }
    pools = { bad = {
      platform = "gpu-h200-sxm", preset = "8gpu-128vcpu-1600gb", fixed_node_count = 1, gpu_cluster_key = "missing"
    } }
  }
  expect_failures = [var.pools]
}

run "single_gpu_infiniband" {
  command = plan
  variables {
    pools = { bad = {
      platform = "gpu-h100-sxm", preset = "1gpu-16vcpu-200gb", fixed_node_count = 1, gpu_cluster_key = "training"
    } }
  }
  expect_failures = [var.pools]
}

run "fake_capabilities" {
  command = plan
  variables {
    pools = { bad = {
      platform    = "gpu-h200-sxm", preset = "8gpu-128vcpu-1600gb", fixed_node_count = 1
      node_labels = { "nvidia.com/gpu.product" = "fake" }
    } }
  }
  expect_failures = [var.pools]
}

run "simulation_cannot_request_gpu" {
  command = plan
  variables { simulation = { enabled = true, platform = "gpu-h200-sxm" } }
  expect_failures = [var.simulation]
}

run "initial_identity" {
  command = apply
  variables { simulation = { enabled = true } }
}

run "adding_pool_preserves_ids" {
  command = apply
  variables {
    simulation = { enabled = true }
    pools = {
      training   = { platform = "gpu-h200-sxm", preset = "8gpu-128vcpu-1600gb", fixed_node_count = 2, gpu_cluster_key = "training" }
      inference  = { platform = "gpu-h100-sxm", preset = "1gpu-16vcpu-200gb", autoscaling = { min_node_count = 0, max_node_count = 3 } }
      experiment = { platform = "gpu-h100-sxm", preset = "1gpu-16vcpu-200gb", fixed_node_count = 1 }
    }
  }
  assert {
    condition     = output.pools["training"].id == run.initial_identity.pools["training"].id && output.pools["inference"].id == run.initial_identity.pools["inference"].id
    error_message = "Adding a named pool must not replace existing pools."
  }
}

run "removing_pool_preserves_ids" {
  command = apply
  variables { simulation = { enabled = true } }
  assert {
    condition     = length(output.pools) == 2 && output.pools["training"].id == run.initial_identity.pools["training"].id && output.pools["inference"].id == run.initial_identity.pools["inference"].id
    error_message = "Removing a pool must not replace the other pools."
  }
}
