# Multiple GPU pools, with CPU simulation

This example calls the complete `k8s-training` solution with a system CPU group and
two independently configured GPU pools. By default, both GPU pools are simulated
with real `cpu-d3` / `4vcpu-16gb` nodes. No GPUs or NVIDIA operators are created.
Training uses a fixed node; inference starts at one node and can autoscale to two.
All three initial nodes use 64-GiB boot disks in simulation.

Run from this directory, which has independent Terraform state. Do not use the
parent solution's `environment.sh`: it configures a shared backend and creates IAM
resources that this example does not need.

```sh
export NEBIUS_IAM_TOKEN="$(nebius iam get-access-token)"
export TF_VAR_iam_token="$NEBIUS_IAM_TOKEN"
export TF_VAR_parent_id="project-..."
export TF_VAR_tenant_id="tenant-..."
export TF_VAR_subnet_id="vpcsubnet-..."
export TF_VAR_region="eu-north1"
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"

terraform init
terraform plan -out=simulation.plan
terraform apply simulation.plan
terraform output -json gpu_pools > pools.json
nebius mk8s cluster get-credentials \
  --id "$(terraform output -json cluster | jq -r .id)" \
  --external --kubeconfig ./simulation.kubeconfig
python3 ../../pool-validation/smoke.py \
  --kubeconfig ./simulation.kubeconfig --inventory ./pools.json \
  --scale-pool inference
```

Keep credentials, state, plans, inventory, and kubeconfig local. The subnet must
support outbound image pulls (for example via NAT). The example leaves observability,
shared storage, and additional workload operators disabled.

After testing, remove the dedicated cluster and its pools:

```sh
terraform plan -destroy
terraform destroy
```

For real GPU use, start a **separate deployment/state**, explicitly set `simulate=false`,
and provide `gpu_pools` using shapes actually available in the target region. The
default example hardware expresses test intent, not a claim of regional GPU availability.
The parent solution's `pool_gpu_clusters` input can define optional InfiniBand domains.
Use the `gpu_pools` output's selectors and tolerations for training Jobs and inference
Deployments, adding real GPU limits to their containers. Benchmark each workload before
choosing which GPU flavor is best; the module does not make that decision automatically.
