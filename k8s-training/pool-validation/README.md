# Live CPU pool validation

See the [recorded live validation results](VALIDATION.md).

`smoke.py` uses an explicit kubeconfig and the `gpu_pools` Terraform output. It creates
a unique namespace, tests real Kubernetes behavior, then deletes that namespace even
when a test fails. It never changes node labels, taints, or extended resources.

```sh
python3 smoke.py --kubeconfig /path/to/test.kubeconfig \
  --inventory /path/to/pools.json --scale-pool inference
```

Checks:

- Every named pool has Ready nodes marked as simulated, with no allocatable NVIDIA resources.
- A CPU pod using each pool's selector and tolerations runs on that pool.
- A pod targeting a tainted pool without its toleration is rejected by the scheduler.
- A pod requesting a real GPU remains unschedulable for insufficient GPU resources.
- With `--scale-pool`, two 2-vCPU pods cause a simulated 4-vCPU pool to grow from one
  node to at least two, run on different nodes, and leave the other pools unchanged.

The optional scaling check requires one initial node and an autoscaling maximum of
at least two. Use the [multi-pool example](../examples/multi-pool). The test does not
verify scale-in timing or GPU autoscaling; a CPU result must not be reported as GPU
readiness, CUDA/NCCL validation, or a performance benchmark.

After the smoke test, use Terraform to add a third pool, compare the existing pool IDs,
and remove it again. Review each plan: unrelated pools must not be replaced. A repeat
plan should have no changes after the control plane has converged. Destroy the dedicated
test deployment when finished; deleting the smoke namespace alone does not delete nodes.
