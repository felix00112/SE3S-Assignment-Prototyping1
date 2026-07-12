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
```

## Tested Scenarios

We currently use and document only two tested scenarios for the assignment write-up and demo:

- `constant_load.js`
  the baseline scenario for comparing throughput and latency across `1`, `3`, and `5` node deployments
- `combined_gates.js`
  the realistic overload scenario where both the per-user rate limiter (`429`) and the admission gate (`503`) become visible

This test selection is intentional:

- `constant_load.js` uses a fresh user per request, so it is good for a clean baseline comparison
- that also means the rate limiter does almost nothing in `constant_load.js`
- `combined_gates.js` is the scenario that shows the protection mechanisms actually doing work

`constant_load.js` uses `K6_VUS` and `K6_DURATION`. Typical baseline overrides:

```bash
K6_VUS=100
K6_DURATION=2m
```

`combined_gates.js` **demonstrates both protection layers working as intended in a
single run** — it is a *correctness* demo of the two gates, **not** an API stress test.
The two gates are antagonistic (the rate limiter runs first in the request path, so
whatever it throttles never reaches the admission gate), so instead of one crowd it runs
**two concurrent populations**, one per gate:

- **`bots`** — a small pool of `BOTS_VUS` (default 20) **stable** ids (`bot-user-<VU>`)
  hammering closed-loop as the same users. Each blows past its per-user token bucket →
  **429** (rate limiter). Their admitted share is tiny, so they barely touch the queue.
- **`flood`** — a legit flash-sale crowd, **unique** uuid per request, offered
  **open-loop** at `FLOOD_RATE` (default **250/s**). Fresh users pass the rate limiter
  and enqueue faster than the worker drains → **503** (admission gate).

Both fire independently, and every sample carries a `role` tag (`bots`/`flood`) plus
k6's built-in `scenario` tag, so the 429s and 503s attribute cleanly (filter
`rejected_rate_limited{role:bots}` and `rejected_admission{role:flood}`). Reports the
`accepted` / `rejected_rate_limited` / `rejected_admission` counters from
`lib/outcome.js`.

**Sizing (why 250/s, not thousands):** the GCP worker drains only **~100/s**
(`WORKER_BATCH_SIZE=100` per `WORKER_INTERVAL_SECONDS=1.0`), so a modest 250/s flood is
already ~2.5x the drain — it fills the 500-deep queue in a few seconds and produces
sustained 503s, while sitting well under the API's serving capacity (a single uvicorn
worker with a sync endpoint handles only a few hundred req/s per node). **Keep this low
on purpose.** Pushing `FLOOD_RATE` into the thousands doesn't demonstrate the gate any
better — it just saturates the API's front door, and you get **`EOF` /
`server closed idle connection`** (dropped TCP connections) *instead of* clean 503s.
That's front-door overload, not admission shedding — if you see it, **lower**
`FLOOD_RATE`.

**Keep the worker running**, or the queue never drains and *everything* trivially
becomes 503 (which proves nothing). Knobs: `COMBINED_DURATION`, `BOTS_VUS`,
`FLOOD_RATE`, `FLOOD_PREALLOCATED_VUS`, `FLOOD_MAX_VUS` (**not** `K6_VUS` /
`K6_DURATION` — reserved, they'd collapse the scenarios block into a single closed
loop). Defaults work out-of-the-box; you shouldn't need to pass anything:

```bash
docker run --rm -e BASE_URL=http://host.docker.internal:8000 -e EVENT_ID=1 \
  -v "$(pwd)/tests/k6:/scripts:ro" grafana/k6:latest run /scripts/combined_gates.js
```


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
scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID constant_load
scripts/gcp/reset.sh -p YOUR_PROJECT_ID
scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID combined_gates
```

Tested baseline run:

```bash
K6_VUS=100 K6_DURATION=2m scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID constant_load
```

Tested realistic protection-layer run:

```bash
scripts/gcp/reset.sh -p YOUR_PROJECT_ID
scripts/gcp/run-tests.sh -p YOUR_PROJECT_ID combined_gates
```
