# This example has its own Terraform state. CPU simulation is the default.
# Never switch an existing simulation cluster to real GPUs in place.
variable "parent_id" { type = string }
variable "tenant_id" { type = string }
variable "subnet_id" { type = string }
variable "region" { type = string }
variable "iam_token" {
  type      = string
  sensitive = true
}
variable "ssh_public_key" { type = string }
variable "cluster_name" {
  type    = string
  default = "multi-pool-simulation"
}
variable "simulate" {
  type    = bool
  default = true
}
variable "gpu_pools" {
  description = "GPU intent; actual hardware is substituted when simulate=true. Verify real shapes in your region before disabling simulation."
  type        = any
  default = {
    training = {
      platform         = "gpu-h200-sxm"
      preset           = "8gpu-128vcpu-1600gb"
      fixed_node_count = 1
      node_labels      = { "workload.nebius.com/type" = "training" }
    }
    inference = {
      platform    = "gpu-h100-sxm"
      preset      = "1gpu-16vcpu-200gb"
      autoscaling = { min_node_count = 1, max_node_count = 2 }
      node_labels = { "workload.nebius.com/type" = "inference" }
    }
  }
}

module "cluster" {
  source = "../.."

  parent_id       = var.parent_id
  tenant_id       = var.tenant_id
  subnet_id       = var.subnet_id
  region          = var.region
  iam_token       = var.iam_token
  cluster_name    = var.cluster_name
  ssh_public_key  = { key = var.ssh_public_key }
  gpu_pools       = var.gpu_pools
  pool_simulation = { enabled = var.simulate }

  cpu_nodes_platform         = "cpu-d3"
  cpu_nodes_preset           = "4vcpu-16gb"
  cpu_nodes_fixed_count      = 1
  cpu_disk_size              = "64"
  gpu_nodes_driverfull_image = true
  enable_k8s_node_group_sa   = false
  enable_nebius_o11y_agent   = false
  enable_grafana             = false
  enable_prometheus          = false
  loki                       = { enabled = false }
}

output "cluster" { value = module.cluster.kube_cluster }
output "gpu_pools" { value = module.cluster.gpu_pools }
