# GCP Load Testing Runbook

This runbook describes the tested GCP testing workflow for the booking prototype.

We currently use only two tested `k6` scenarios:

- `constant_load`
  the baseline scenario for comparing the `1`, `3`, and `5` node deployments
- `combined_gates`
  the realistic protection-layer scenario where the rate limiter and admission gate both come into play

This is intentional:

- `constant_load` is good for baseline throughput and latency comparisons across cluster sizes
- `constant_load` uses a fresh user per request, so the per-user rate limiter does almost nothing there
- `combined_gates` adds the realistic overload behavior by exercising both `429` rate limiting and `503` admission shedding in one run

## Before You Start

Make sure these are true first:

- your local branch contains the latest GCP and `k6` changes
- that branch is pushed to GitHub
- `gcloud auth application-default login` has been run
- the Compute Engine API is enabled in your GCP project

The GCP VMs clone from GitHub during startup, so local-only changes are not enough.

## Quick Path

The tested flow uses the helper scripts in [scripts/gcp](/Users/felixhauptmann/PycharmProjects/SE3S-Assignment-Prototyping1/scripts/gcp:1):

```bash
scripts/gcp/deploy.sh -p PROJECT_ID -n 3
scripts/gcp/run-tests.sh -p PROJECT_ID constant_load
scripts/gcp/reset.sh -p PROJECT_ID
scripts/gcp/run-tests.sh -p PROJECT_ID combined_gates
scripts/gcp/destroy.sh -p PROJECT_ID
```

`run-tests.sh` downloads the results into `results/<timestamp>-<scenario>/k6-out/`:

- `raw-*.csv` for time-series analysis and plots
- `summary-*.json` for headline aggregate metrics

You can summarize a downloaded JSON report with:

```bash
python3 scripts/gcp/summarize.py results/TIMESTAMP-SCENARIO/k6-out/summary-REPORT.json
```

## 1. Deploy The Environment

From the repository root:

```bash
scripts/gcp/deploy.sh -p YOUR_PROJECT_ID -n 3
```

Important notes:

- `-n 1|3|5` selects the horizontal scaling configuration
- all three configurations use the same instance type
- node `0` hosts Redis, the worker, and the `Nginx` load balancer
- the remaining nodes are stateless API replicas
- the public entry point is the load balancer on port `80`

For vertical-scaling comparisons, keep `-n` fixed and change the machine type:

```bash
scripts/gcp/deploy.sh -p YOUR_PROJECT_ID -n 3 -m e2-standard-2
```

## 2. Verify The Deployment

Check the health endpoint:

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

## 3. Run The Baseline Test

Use `constant_load` as the baseline scenario:

```bash
K6_VUS=100 K6_DURATION=2m scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID constant_load
```

Why this is the baseline:

- it gives a simple steady-load comparison across `1`, `3`, and `5` node clusters
- it is good for comparing throughput and latency
- it does not meaningfully exercise the per-user rate limiter, because it uses fresh users

Tested comparison workflow:

```bash
for N in 1 3 5; do
  scripts/gcp/deploy.sh -p YOUR_PROJECT_ID -n "$N"
  K6_VUS=100 K6_DURATION=2m scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID constant_load
  scripts/gcp/destroy.sh -p YOUR_PROJECT_ID
done
```

Useful metrics to compare:

- total requests handled
- latency percentiles
- accepted bookings

This baseline is the clearest way to show how the API tier behaves as you scale the cluster size.

## 4. Run The Realistic Protection Test

Use `combined_gates` as the realistic scenario:

```bash
scripts/gcp/reset.sh -p YOUR_PROJECT_ID
scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID combined_gates
```

Why this scenario matters:

- it demonstrates the per-user rate limiter with clean `429` responses
- it demonstrates the admission gate with clean `503` responses
- it shows both protection layers in one realistic flash-sale style run

This is the tested scenario for showing that the system does not just scale, but also protects itself under overload.

## 5. Watch The Deployment During A Run

Container CPU and memory:

```bash
gcloud compute ssh se3s-mvp-vm --zone europe-west3-a --project YOUR_PROJECT_ID --command \
"sudo docker stats --no-stream"
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

## 6. Interpreting The Two Tests

`constant_load`:

- use it to compare baseline throughput and latency across cluster sizes
- do not use it to argue that the rate limiter was validated

`combined_gates`:

- use it to show realistic overload handling
- use it to explain where `429` and `503` come from
- use it to demonstrate that multiple protection layers work together

Together, these two tests tell the story we actually care about:

- how the system behaves under a clean baseline load
- how the system behaves when all protection mechanisms come into action

## Troubleshooting

### `curl .../health` fails

Check:

```bash
gcloud compute ssh se3s-mvp-vm --zone europe-west3-a --project YOUR_PROJECT_ID --command \
"sudo journalctl -u google-startup-scripts.service -n 200 --no-pager"
```

### `docker-compose` fails with `ContainerConfig`

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

That usually means empty `K6_*` variables were injected into the remote helper. If needed, recreate the load-generator VM or refresh `/usr/local/bin/run-k6.sh`.

## Destroy

```bash
scripts/gcp/destroy.sh -p YOUR_PROJECT_ID
```
