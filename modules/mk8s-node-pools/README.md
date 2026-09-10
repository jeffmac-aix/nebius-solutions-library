# Managed Kubernetes GPU pools

Creates independently configured GPU node groups in an existing Managed Kubernetes
cluster. The caller owns the cluster, system CPU nodes, and cluster-wide GPU software.
See [the complete example](../../k8s-training/examples/multi-pool).

`pools` is a map keyed by stable pool names. Each entry requires `platform`, `preset`,
and exactly one of `fixed_node_count` or `autoscaling` (integer `min_node_count` and
`max_node_count`). Optional settings include `name`, disk type/size, public IPs,
preemptibility, filesystem attachment, node labels, and taints. Kubernetes node
labels are set in the node template; resource metadata labels do not control scheduling.

Pool keys identify Terraform resources. Adding/removing a key only adds/removes that
pool. Renaming a key changes its Terraform identity unless accompanied by a state move.
Changing hardware or node-template properties can roll or replace nodes, even when
the key is unchanged; review the Terraform plan and Nebius update behavior.

`gpu_clusters` defines named InfiniBand placement domains. A pool can reference one
with `gpu_cluster_key`, or attach an existing GPU cluster with
`existing_gpu_cluster_id`. The module checks references and 8-GPU presets. The caller
must verify platform/preset/fabric availability and compatibility in the target region,
and that existing GPU clusters are in the same project. Different pools can share a
compatible domain; a distributed job should select a homogeneous compatible pool.

`drivers_preset` configures one image driver version across real GPU pools. Set it to
null only when the caller installs and validates a compatible GPU operator. This module
does not install operators, discover hardware, or optimize GPU choice. Whole GPUs are
supported in this version; MIG and custom per-pool NUMA policies are deferred.

The `pools` output includes cloud IDs, requested and actual hardware, `node_selector`,
and Kubernetes-spelled `tolerations`. The default taint is
`nvidia.com/gpu=true:NoSchedule`; callers can override `taints` or explicitly set `[]`.
Tolerations allow access, while selectors/affinity choose eligible nodes. GPU workloads
must also request their actual GPU resource, normally `nvidia.com/gpu`.

## CPU simulation

`simulation = { enabled = true }` substitutes CPU platform/preset and a smaller boot
disk for every pool. It retains identities, scaling settings, labels, and taints,
but omits GPU clusters, GPU drivers, and GPU preemption settings. Outputs distinguish
requested GPU intent from actual CPU hardware. Simulation never advertises fake
`nvidia.com/*` resources or capability labels.

Use separate state and a separate cluster for simulation. Turning it off changes
hardware and may replace nodes. CPU tests validate provisioning and scheduling; they
cannot validate CUDA, NVSwitch, InfiniBand, NCCL, GPU throughput, GPU quota/capacity,
or GPU-specific autoscaler behavior.

## Local tests

```sh
terraform init -backend=false
terraform test
```

These module tests mock the Nebius provider and create no cloud infrastructure.
They cover configuration validation, hardware substitution, and stable identities.
For real scheduling and autoscaling tests, see [pool validation](../../k8s-training/pool-validation).
