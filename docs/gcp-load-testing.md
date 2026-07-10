# GCP Load Testing Runbook

This runbook is the shortest reliable path for deploying the booking MVP to GCP and running `k6` load tests from the dedicated load-generator VM.

## Before You Start

Make sure these are true first:

- your local branch contains the latest GCP and `k6` fixes
- that branch is pushed to GitHub
- `gcloud auth application-default login` has been run
- the Compute Engine API is enabled in your GCP project

The GCP VMs clone from GitHub during startup, so local-only changes are not enough.

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
- `node_count=1` is the simplest baseline; use `3` or `5` for comparison runs

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
