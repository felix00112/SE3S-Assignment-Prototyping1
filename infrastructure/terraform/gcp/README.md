# GCP Terraform MVP

This is the first deliberately small Terraform deployment for the booking workflow MVP.

It creates:

- one custom VPC and subnet
- firewall rules for SSH and the FastAPI port
- `1`, `3`, or `5` Ubuntu Compute Engine VMs using the same machine type
- Docker Compose on every VM
- Redis and the single worker on the coordinator node (node 0)
- a FastAPI API replica on **every** node (the tier that scales horizontally)
- an optional dedicated `k6` load-generator VM for running tests from inside GCP

The goal is to keep the assignment deployment reproducible without jumping straight to managed Redis, Kubernetes, or autoscaling.

## Why This Shape

The API is the first component to bottleneck under load, so this setup scales the **API tier** horizontally while keeping the stateful parts singular. The assignment asks for `1` / `3` / `5` node configurations, all using the same instance type — so `node_count` is the number of API-serving VMs, and the single-node config runs the whole app on one VM.

Node 0 (the coordinator) hosts the one Redis, the one worker, an API replica, and an **Nginx load balancer**. Nodes 1..N-1 are **stateless API-only replicas** that connect to node 0's Redis over the private VPC IP. Redis is only opened to the deployment subnet by the Terraform firewall rule. There is one shared queue and one shared seat counter, so correctness (the atomic Lua reserve) is preserved no matter how many API replicas run.

The load balancer (Nginx, `least_conn`) runs on node 0 and fans out across every API replica's `:8000` (backends are static private IPs templated by Terraform). It is the **public entry point on port 80** — `api_url` points at it, and load tests should target it. Individual replicas stay reachable at their own `:8000` (see `api_urls`) for debugging. Nginx re-resolves nothing at runtime, but since each config (1/3/5) is a separate deployment, it picks up the full fixed backend set at startup.

If `load_generator_enabled=true`, Terraform also creates a separate VM that installs Docker, clones this repository, and exposes a `run-k6.sh` helper for the `tests/k6` scenarios.

Node layout:

```text
1 node:
  se3s-mvp-vm: LB(:80) + API + Redis + worker

3 nodes:
  se3s-mvp-vm:    LB(:80) + API + Redis + worker
  se3s-mvp-api-2: API   -> redis@coordinator
  se3s-mvp-api-3: API   -> redis@coordinator

5 nodes:
  se3s-mvp-vm:    LB(:80) + API + Redis + worker
  se3s-mvp-api-2: API   -> redis@coordinator
  se3s-mvp-api-3: API   -> redis@coordinator
  se3s-mvp-api-4: API   -> redis@coordinator
  se3s-mvp-api-5: API   -> redis@coordinator

Public traffic -> se3s-mvp-vm:80 (Nginx) -> least_conn across all API :8000
```

## Prerequisites

- Terraform `>= 1.5`
- Google Cloud SDK authenticated with application default credentials
- a GCP project with Compute Engine API enabled
- the selected `source_ref` pushed to the configured Git repository

```bash
gcloud auth application-default login
gcloud services enable compute.googleapis.com --project YOUR_PROJECT_ID
```

## Deploy

```bash
cd infrastructure/terraform/gcp
terraform init
terraform apply \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="source_ref=gcp-terraform-mvp" \
  -var="node_count=1" \
  -var="worker_batch_size=100" \
  -var="worker_interval_seconds=1" \
  -var="worker_synthetic_dummy_mode=false"
```

Use `node_count=3` or `node_count=5` for the other comparison deployments.

To provision a dedicated load-generator VM as well:

```bash
terraform apply \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="source_ref=gcp-terraform-mvp" \
  -var="node_count=3" \
  -var="load_generator_enabled=true" \
  -var="initial_seats=100000" \
  -var="worker_batch_size=100" \
  -var="worker_interval_seconds=1" \
  -var="worker_synthetic_dummy_mode=true"
```

For load runs, set `initial_seats` high enough that requests do not immediately transition into `sold_out`.

Worker constant-work settings are now explicit Terraform inputs:

- `worker_batch_size`
- `worker_interval_seconds`
- `worker_synthetic_dummy_mode`

That means you can run the same node-count deployment with different worker pacing or with synthetic dummy slots enabled, without editing files on the VM.

If you deployed the older single-VM Terraform version first, destroy it before applying this node-count version. That avoids Terraform replacing the original VM while you are still debugging:

```bash
terraform destroy -var="project_id=YOUR_PROJECT_ID"
```

After apply finishes, Terraform prints `api_url`.

If the optional load-generator is enabled, Terraform also prints `load_generator_ssh_command`.

## Helper Scripts

If you do not want to run the raw Terraform and `gcloud` commands manually every time, use the helper scripts in [scripts/gcp](/Users/felixhauptmann/PycharmProjects/SE3S-Assignment-Prototyping1/scripts/gcp:1):

```text
scripts/gcp/
├── deploy.sh
├── destroy.sh
├── reset.sh
├── run-tests.sh
└── summarize.py
```

These wrap the most common deployment and evaluation steps:

- `scripts/gcp/deploy.sh`
  deploys the cluster with Terraform
- `scripts/gcp/run-tests.sh`
  runs a `k6` scenario from the dedicated load-generator VM and downloads the reports
- `scripts/gcp/reset.sh`
  resets Redis on the coordinator and reseeds the seat counter between runs
- `scripts/gcp/destroy.sh`
  destroys the deployed GCP environment
- `scripts/gcp/summarize.py`
  prints headline metrics from a downloaded `k6` summary JSON file

### Wrapper-Based Quick Path

Deploy a cluster with a dedicated load generator:

```bash
scripts/gcp/deploy.sh -p YOUR_PROJECT_ID -n 3
```

Useful flags:

- `-n 1|3|5` selects the horizontal scaling configuration
- `-m MACHINE_TYPE` changes the VM type for vertical-scaling comparisons
- `-s SEATS` sets the initial seat inventory
- `-r SOURCE_REF` selects the pushed Git branch or commit to deploy
- `-g true|false` enables or disables the dedicated load-generator VM

Example:

```bash
scripts/gcp/deploy.sh -p YOUR_PROJECT_ID -n 5 -m e2-standard-2 -s 100000 -r your-branch -g true
```

Run a test scenario:

```bash
scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID constant_load
scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID combined_gates
```

Examples with overrides:

```bash
K6_VUS=100 K6_DURATION=2m scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID constant_load
scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID combined_gates
```

Reset Redis between repeated runs on the same cluster:

```bash
scripts/gcp/reset.sh -p YOUR_PROJECT_ID
scripts/gcp/reset.sh -p YOUR_PROJECT_ID -s 100000 -e 1
```

Destroy the environment after you finish measuring:

```bash
scripts/gcp/destroy.sh -p YOUR_PROJECT_ID
```

Summarize a downloaded `k6` result manually:

```bash
python3 scripts/gcp/summarize.py results/TIMESTAMP-SCENARIO/k6-out/summary-REPORT.json
```

### Tested Workflow

For each configuration (`1`, `3`, or `5` nodes):

```bash
scripts/gcp/deploy.sh -p YOUR_PROJECT_ID -n 3
scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID constant_load
scripts/gcp/reset.sh -p YOUR_PROJECT_ID
scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID combined_gates
scripts/gcp/destroy.sh -p YOUR_PROJECT_ID
```

## Smoke Test

```bash
curl "$(terraform output -raw api_url)/health"

curl -X POST "$(terraform output -raw api_url)/events/1/book" \
  -H "content-type: application/json" \
  -d '{"user_id":"user-1"}'
```

Check the reservation status with the returned `reservation_id`:

```bash
curl "$(terraform output -raw api_url)/reservations/RESERVATION_ID"
```

## Destroy

```bash
terraform destroy -var="project_id=YOUR_PROJECT_ID"
```
