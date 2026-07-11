# GCP Load Testing Runbook

This runbook is the shortest reliable path for deploying the booking MVP to GCP and running `k6` load tests from the dedicated load-generator VM.

## Before You Start

Make sure these are true first:

- your local branch contains the latest GCP and `k6` fixes
- that branch is pushed to GitHub
- `gcloud auth application-default login` has been run
- the Compute Engine API is enabled in your GCP project

The GCP VMs clone from GitHub during startup, so local-only changes are not enough.

## Quick Path (wrapper scripts)

Three parameterized helpers wrap the raw Terraform/gcloud commands:

```bash
scripts/gcp/deploy.sh   -p PROJECT_ID -n 3            # deploy a 3-node cluster + load generator
scripts/gcp/run-tests.sh -p PROJECT_ID constant_load # run a scenario, fetch reports, print headline metrics
scripts/gcp/destroy.sh  -p PROJECT_ID                # tear everything down
```

`deploy.sh` flags: `-n` node_count (1/3/5), `-m` machine_type (raise for vertical
scaling), `-s` initial_seats, `-r` source_ref (defaults to your current branch),
`-g` load generator on/off. `run-tests.sh` accepts the scenario name and passes
through `K6_VUS` / `K6_DURATION` / `K6_STAGES`.

### Reports & plots

`run-tests.sh` pulls two files back into `results/<timestamp>-<scenario>/k6-out/`:

- `raw-*.csv` — per-sample **time series** (throughput, latency, VUs over time, and
  per-request `status`) — feed this straight into your plotting tool.
- `summary-*.json` — end-of-run aggregates, including the `accepted`,
  `rejected_rate_limited` (429) and `rejected_admission` (503) counters.

`scripts/gcp/summarize.py <summary.json>` prints the headline numbers (throughput,
latency percentiles, users, accepted/rejected). The rest of this document is the
manual, step-by-step version of the same flow.

## 1. Deploy The Environment

From the repo root:

```bash
terraform -chdir=infrastructure/terraform/gcp init

terraform -chdir=infrastructure/terraform/gcp apply \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="source_ref=YOUR_BRANCH_OR_COMMIT" \
  -var="node_count=1" \
  -var="load_generator_enabled=true" \
  -var="initial_seats=100000"
```

Notes:

- `source_ref` should be a pushed branch name or a commit SHA
- `initial_seats=100000` avoids an immediate `sold_out` result during throughput tests
- **`node_count` sets how many API nodes you get** — it must be `1`, `3`, or `5`
  (the assignment's single-node / 3-node / 5-node configs, all one instance type).
  Node 0 hosts Redis + the single worker + the Nginx load balancer; nodes 1..N-1
  are stateless API-only replicas. See "Choosing The Cluster Size" below.
- `api_url` resolves to the **Nginx load balancer on node 0 (port 80)**, which
  distributes across all API replicas — always send load here, not at a single node.

## Choosing The Cluster Size (node_count)

`node_count` is the single knob for horizontal scaling — the number of API-serving
VMs. Change it per deploy:

```bash
-var="node_count=1"   # config (a): 1 node  (LB + API + Redis + worker on one VM)
-var="node_count=3"   # config (b): 3 nodes (coordinator + 2 API replicas)
-var="node_count=5"   # config (c): 5 nodes (coordinator + 4 API replicas)
```

To vertically scale instead (assignment bonus 2d), keep `node_count` fixed and raise
the machine size, e.g. `-var="machine_type=e2-standard-2"`.

### Scaling comparison workflow (a / b / c)

Each configuration is a separate deploy → measure → destroy cycle, using the wrapper
scripts (which handle apply, the load-balancer readiness wait, report fetch, and
destroy):

```bash
for N in 1 3 5; do
  scripts/gcp/deploy.sh -p YOUR_PROJECT_ID -n "$N"

  # 300 VUs so the offered load actually SATURATES the API tier. With the default
  # 20 VUs the test is client-limited (~20 / latency req/s) and the 1/3/5 curve
  # looks flat no matter how many API nodes you add. run-tests.sh waits for the LB
  # before starting, fetches the reports, and prints the headline numbers.
  K6_VUS=300 K6_DURATION=1m scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID constant_load

  scripts/gcp/destroy.sh -p YOUR_PROJECT_ID
done
```

Which metric to plot:

- **Requests handled/s** (`http_reqs` rate = accepted + cleanly-rejected 503) is the
  API + load-balancer tier capacity. This should **rise from 1 → 3 → 5 nodes** — the
  "horizontal scaling works" result.
- **Accepted bookings/s** (the `accepted` counter / duration) is gated by the single
  worker, so it stays roughly **flat** — that plateau is your scalability-limitations
  point.

Tip: sweep the load (e.g. `K6_VUS=50 150 300 600`) at each node count to find where
each cluster size saturates; the peak requests-handled/s per size is the scaling curve.

## 2. Verify The API Before Load Testing

Wait until the coordinator VM finishes its startup script, then check:

```bash
curl "$(terraform -chdir=infrastructure/terraform/gcp output -raw api_url)/health"
```

Expected result:

```json
{"status":"healthy"}
```

If that fails, inspect the coordinator:

```bash
gcloud compute ssh se3s-mvp-vm --zone europe-west3-a --project YOUR_PROJECT_ID --command \
"cd /opt/se3s/app && sudo docker-compose -f docker-compose.gcp.yml ps && echo '--- API LOGS ---' && sudo docker-compose -f docker-compose.gcp.yml logs --tail=100 api"
```

## 3. Run A Baseline Load Test

From the repo root:

```bash
scripts/run-gcp-load-test.sh constant_load
```

This uses the default `constant_load.js` profile:

- `20` VUs
- `1m` duration
- unique `user_id` per request

That means it measures overall booking throughput, not per-user rate limiting.

## 4. Override Load Shape

Higher steady concurrency:

```bash
K6_VUS=50 K6_DURATION=1m scripts/run-gcp-load-test.sh constant_load
K6_VUS=100 K6_DURATION=2m scripts/run-gcp-load-test.sh constant_load
```

Ramp-up / ramp-down scenario:

```bash
scripts/run-gcp-load-test.sh dynamic_load
```

Custom dynamic stages:

```bash
K6_STAGES='[{"duration":"2m","target":100},{"duration":"3m","target":400},{"duration":"1m","target":0}]' \
  scripts/run-gcp-load-test.sh dynamic_load
```

## 5. Watch The Deployment While The Test Runs

Container CPU and memory:

```bash
gcloud compute ssh se3s-mvp-vm --zone europe-west3-a --project YOUR_PROJECT_ID --command \
"sudo docker stats --no-stream"
```

Repeated samples during a run:

```bash
gcloud compute ssh se3s-mvp-vm --zone europe-west3-a --project YOUR_PROJECT_ID --command \
"for i in \$(seq 1 10); do echo '--- sample' \$i; sudo docker stats --no-stream; sleep 2; done"
```

Booking queue length:

```bash
gcloud compute ssh se3s-mvp-vm --zone europe-west3-a --project YOUR_PROJECT_ID --command \
"cd /opt/se3s/app && for i in \$(seq 1 10); do sudo docker-compose -f docker-compose.gcp.yml exec -T redis redis-cli LLEN event:1:booking_queue; sleep 2; done"
```

Worker logs:

```bash
gcloud compute ssh se3s-mvp-vm --zone europe-west3-a --project YOUR_PROJECT_ID --command \
"cd /opt/se3s/app && sudo docker-compose -f docker-compose.gcp.yml logs --tail=50 worker"
```

## 6. Rate Limiter Caveat

The current `constant_load.js` and `dynamic_load.js` intentionally generate a fresh UUID per request.

That means:

- good for measuring throughput
- not good for testing per-user throttling

If you want to test the rate limiter, use a script that sends repeated requests with the same `user_id`.

## Troubleshooting

### `curl .../health` fails

Check:

```bash
gcloud compute ssh se3s-mvp-vm --zone europe-west3-a --project YOUR_PROJECT_ID --command \
"sudo journalctl -u google-startup-scripts.service -n 200 --no-pager"
```

### `docker-compose` fails with `ContainerConfig`

This can happen on older `docker-compose` v1 installs when recreating an existing container in place.

Use:

```bash
gcloud compute ssh se3s-mvp-vm --zone europe-west3-a --project YOUR_PROJECT_ID --command \
"cd /opt/se3s/app && sudo docker-compose -f docker-compose.gcp.yml down && sudo docker-compose -f docker-compose.gcp.yml up -d --build"
```

### `k6` says a JS module is missing

Make sure the latest branch is pushed and that the load-generator VM has pulled it:

```bash
gcloud compute ssh se3s-mvp-loadgen --zone europe-west3-a --project YOUR_PROJECT_ID --command \
"cd /opt/se3s/app && sudo git fetch --all && sudo git checkout YOUR_BRANCH && sudo git pull --ff-only"
```

### The test runs with `1 VU` and `1 iteration`

That means empty `K6_*` variables were injected into the load-generator helper. Fresh Terraform deployments should now avoid this, but if an older loadgen VM exists, recreate it or refresh `/usr/local/bin/run-k6.sh`.

## Destroy

```bash
terraform -chdir=infrastructure/terraform/gcp destroy \
  -var="project_id=YOUR_PROJECT_ID"
```
