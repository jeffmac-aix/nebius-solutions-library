variable "parent_id" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "k8s_version" {
  type    = string
  default = null
}

variable "service_account_id" {
  type    = string
  default = null
}

variable "drivers_preset" {
  description = "One image driver preset for all real GPU pools; null delegates drivers to the cluster operator."
  type        = string
  default     = "cuda13.0"
}

variable "cloud_init" {
  description = "Cloud-init per pool, supplied by the caller."
  type        = map(string)
  default     = {}
}

variable "filesystems" {
  type = list(object({
    attach_mode         = string
    mount_tag           = string
    existing_filesystem = object({ id = string })
  }))
  default = []
}

variable "gpu_clusters" {
  description = "Named InfiniBand placement domains; pools reference these keys."
  type = map(object({
    infiniband_fabric = string
    name              = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for c in var.gpu_clusters : trimspace(c.infiniband_fabric) != ""])
    error_message = "Every GPU cluster needs a nonempty InfiniBand fabric."
  }
}

variable "simulation" {
  description = "CPU-only scheduling simulation. Never advertises NVIDIA GPU resources. Use a separate cluster/state."
  type = object({
    enabled       = optional(bool, false)
    platform      = optional(string, "cpu-d3")
    preset        = optional(string, "4vcpu-16gb")
    disk_size_gib = optional(number, 64)
  })
  default = {}

  validation {
    condition     = startswith(var.simulation.platform, "cpu-") && !strcontains(var.simulation.preset, "gpu") && var.simulation.disk_size_gib > 0
    error_message = "Simulation must use a CPU platform/preset and a positive disk size."
  }
}

variable "pools" {
  description = "Stable pool keys are Terraform identities. Kubernetes labels belong to node_labels, not resource labels."
  type = map(object({
    name             = optional(string)
    platform         = string
    preset           = string
    fixed_node_count = optional(number)
    autoscaling = optional(object({
      min_node_count = number
      max_node_count = number
    }))
    disk_type               = optional(string, "NETWORK_SSD")
    disk_size_gib           = optional(number, 1023)
    public_ips              = optional(bool, false)
    preemptible             = optional(bool, false)
    gpu_cluster_key         = optional(string)
    existing_gpu_cluster_id = optional(string)
    attach_filesystems      = optional(bool, true)
    node_labels             = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string, "")
      effect = string
    })), [{ key = "nvidia.com/gpu", value = "true", effect = "NO_SCHEDULE" }])
  }))
  default = {}

  validation {
    condition     = alltrue([for k, p in var.pools : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", k)) && length(k) <= 63])
    error_message = "Pool keys must be lowercase DNS labels of at most 63 characters."
  }
  validation {
    condition     = alltrue([for p in var.pools : (p.fixed_node_count == null) != (p.autoscaling == null)])
    error_message = "Set exactly one of fixed_node_count or autoscaling for each pool."
  }
  validation {
    condition = alltrue([for p in var.pools : p.autoscaling == null ? true : (
      p.autoscaling.min_node_count >= 0 && p.autoscaling.max_node_count >= 1 &&
      p.autoscaling.min_node_count <= p.autoscaling.max_node_count &&
      floor(p.autoscaling.min_node_count) == p.autoscaling.min_node_count &&
      floor(p.autoscaling.max_node_count) == p.autoscaling.max_node_count
    )])
    error_message = "Autoscaling requires integer bounds with 0 <= min <= max and max >= 1."
  }
  validation {
    condition     = alltrue([for p in var.pools : p.fixed_node_count == null ? true : p.fixed_node_count >= 0 && floor(p.fixed_node_count) == p.fixed_node_count])
    error_message = "Fixed node counts must be nonnegative integers."
  }
  validation {
    condition     = alltrue([for p in var.pools : startswith(p.platform, "gpu-") && can(regex("^[1-9][0-9]*gpu-", p.preset)) && p.disk_size_gib > 0])
    error_message = "Pools need an explicit GPU platform, GPU preset, and positive disk size (including when simulated)."
  }
  validation {
    condition = alltrue([for p in var.pools :
      (p.gpu_cluster_key == null || p.existing_gpu_cluster_id == null) &&
      (p.gpu_cluster_key == null ? true : contains(keys(var.gpu_clusters), p.gpu_cluster_key)) &&
      (p.gpu_cluster_key == null && p.existing_gpu_cluster_id == null ? true : startswith(p.preset, "8gpu-"))
    ])
    error_message = "Choose a defined GPU cluster key OR an existing GPU cluster ID; InfiniBand requires an 8-GPU preset. Verify regional fabric/platform compatibility separately."
  }
  validation {
    condition     = alltrue(flatten([for p in var.pools : [for t in p.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)]]))
    error_message = "Taint effects use Nebius API spelling: NO_SCHEDULE, PREFER_NO_SCHEDULE, NO_EXECUTE."
  }
  validation {
    condition = alltrue(flatten([for p in var.pools : [for k in keys(p.node_labels) :
      !startswith(k, "nvidia.com/") && !contains(["nebius.com/pool", "nebius.com/simulated", "nebius.com/requested-platform"], k)
    ]]))
    error_message = "Pool identity/simulation labels are reserved; NVIDIA capability labels must be discovered, not supplied."
  }
}
