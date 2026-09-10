# Live validation — 2026-09-10

The complete [multi-pool example](../examples/multi-pool) was deployed to a dedicated
Nebius Managed Kubernetes cluster in `eu-north1`, using CPU simulation. This was a
real cloud deployment and Kubernetes scheduling test.

Environment: Terraform 1.15.8, Nebius provider 0.5.270 (the repository's existing
provider source), Kubernetes v1.36.3, Ubuntu 24.04.4. All nodes used `cpu-d3`,
`4vcpu-16gb`, and 64-GiB boot disks. Initial topology: one system node, one fixed
training node, and one inference node with autoscaling bounds 1–2.

| Check | Result |
|---|---|
| Complete solution validates | Passed |
| Three initial CPU node groups provision and become Ready | Passed |
| Simulated pools expose labels/taints, with no allocatable NVIDIA resources | Passed |
| CPU workloads run on their selected training/inference pools | Passed |
| Missing toleration prevents scheduling onto the selected tainted pool | Passed |
| Real GPU request remains pending with insufficient GPU resources | Passed |
| Two 2-vCPU requests trigger inference scale-out from one node to two | Passed |
| Scale-out pods run on distinct nodes; training node remains unchanged | Passed |
| Repeat Terraform plan after initial deployment | No changes |
| Add temporary experiment pool | One addition; zero changes or deletions |
| Original training/inference pool IDs after addition | Unchanged |
| Remove temporary experiment pool | One deletion; zero additions or changes |
| Original training/inference pool IDs after removal | Unchanged |
| Final Terraform convergence check | No changes |
| Dedicated test deployment destroyed | Passed; Terraform state empty |
| Cluster and all five test VMs absent from Nebius API | Confirmed |

The smoke-test namespace was deleted automatically. The dedicated cluster and all
test VMs were subsequently deleted and their absence verified through the Nebius API.
During teardown, four system disruption budgets were removed only in this disposable
cluster to allow the last system node to drain. Production disruption policies were
not changed by this implementation.

The reusable module's 12 local mocked tests also passed; these only supplement the
live results above. Full-solution mocks were not retained.

## Scope limits

CPU simulation does not establish real GPU availability, driver/CUDA compatibility,
NVSwitch or InfiniBand health, NCCL correctness, GPU performance, MIG behavior, or
GPU-specific autoscaling. Autoscaler scale-in timing and scale-from-zero were not
tested live. The minimal single-system-node topology was not an HA validation.
Migration from an existing real GPU installation still requires a deployment-specific
state move and plan review; this run validated new deployment and named-pool lifecycle.

Project IDs, node IDs, credentials, and Terraform state are not included in this report.

## Follow-up code review

After the live CPU run, pool inputs, locals, and outputs were moved into the
solution's existing file layout. Network Operator installation was restored for
all real GPU pools. The existing H100 NCCL benchmark now accepts a named pool's
worker selector and tolerations, guarded to fixed-size eight-GPU H100 InfiniBand
pools. These follow-up changes have not been deployed to GPU hardware. Terraform
validation and all 12 existing node-pool module tests pass.
Helm lint and named-pool chart rendering also pass; the default rendered manifest
is byte-for-byte identical to the original chart. No new cloud resources were created.
