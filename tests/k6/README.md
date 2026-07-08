# k6 Tests

This folder contains the primary load and stress test scenarios for the booking flow.

## Basic Test Set-Up

Start Docker Compose:

```bash
docker compose up --build
```

Run a scenario locally with the official k6 container:

```bash
docker run --rm \
  -e BASE_URL=http://host.docker.internal:8000 \
  -e EVENT_ID=1 \
  -v "$(pwd)/tests/k6:/scripts:ro" \
  grafana/k6:latest run /scripts/constant_load.js
```

Useful overrides:

```bash
K6_VUS=50
K6_DURATION=3m
K6_STAGES='[{"duration":"1m","target":100},{"duration":"2m","target":300},{"duration":"30s","target":0}]'
```

`constant_load.js` uses `K6_VUS` and `K6_DURATION`.

`dynamic_load.js` uses `K6_STAGES` as a JSON array. If no env vars are supplied, both scripts keep their current defaults.

## Running On GCP

The Terraform MVP can optionally create a dedicated `k6` VM inside GCP. Enable it during deploy:

```bash
cd infrastructure/terraform/gcp
terraform apply \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="source_ref=YOUR_BRANCH_OR_TAG" \
  -var="load_generator_enabled=true" \
  -var="initial_seats=100000"
```

Then run a scenario from the repo root:

```bash
scripts/run-gcp-load-test.sh constant_load
scripts/run-gcp-load-test.sh dynamic_load
```

Example with custom load shape:

```bash
K6_VUS=100 K6_DURATION=5m scripts/run-gcp-load-test.sh constant_load
K6_STAGES='[{"duration":"2m","target":200},{"duration":"3m","target":800},{"duration":"1m","target":0}]' \
  scripts/run-gcp-load-test.sh dynamic_load
```
