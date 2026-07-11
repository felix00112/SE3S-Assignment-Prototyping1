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
STAGES='[{"duration":"1m","target":100},{"duration":"2m","target":300},{"duration":"30s","target":0}]'
```

`constant_load.js` uses `K6_VUS` and `K6_DURATION`.

`dynamic_load.js` uses `STAGES` as a JSON array. If no env vars are supplied, both scripts keep their current defaults.

> Override the ramp with the `STAGES` env var (JSON), **not** `K6_STAGES` — `K6_STAGES`
> is reserved by k6 (it parses it in its own `10s:100,...` format before the script runs)
> and passing JSON there errors out.

`flash_sale.js` models a flash-sale burst: a staged ramp **0 → 50 → 200** VUs (hold,
then drain) combined with a **stable per-VU `user_id`** (`flash-user-<VU>`). Because
the same users hammer the endpoint, it exercises the per-user rate limiter under a
realistic "link just went live" spike. Reports `throttled_requests` plus the
`accepted` / `rejected_rate_limited` / `rejected_admission` counters. Override the ramp
with `STAGES`.

`rate_limit_load.js` also uses `K6_VUS` and `K6_DURATION`, but assigns a **stable
per-VU `user_id`** (`rl-user-<VU>`) instead of a fresh UUID per request. That means
each virtual user repeatedly books as the same user, so requests actually trip the
per-user rate limiter. It reports a `throttled_requests` rate (the share of
responses that came back `429`); `constant_load.js` / `dynamic_load.js` generate a
unique user per request and therefore only measure throughput, never throttling.

`oversell_test.js` is a **correctness** test for the atomic reserve, not a
throughput test. It fires `TOTAL_REQUESTS` bookings (default `EXPECTED_SEATS * 3`)
with a unique user each, follows every accepted booking to its final status, and
asserts via k6 thresholds that `reserved <= EXPECTED_SEATS` (never oversell),
`duplicate == 0`, and no unexpected statuses. **Seed a small seat count first** so
seats actually run out, e.g. `EXPECTED_SEATS=100` with Redis seeded to 100 seats
(locally `redis-cli SET event:1:seats_available 100 && redis-cli DEL event:1:reserved_users`,
or on GCP deploy with `-var="initial_seats=100"`). Knobs: `EXPECTED_SEATS`,
`TOTAL_REQUESTS`, `OVERSELL_VUS`, `K6_MAX_DURATION`, `POLL_INTERVAL`. (It uses
`OVERSELL_VUS`, not `K6_VUS`, because `K6_VUS` is a reserved k6 variable that would
override the fixed-iteration scenario this test relies on.)

`e2e_latency.js` measures the **async pipeline latency** — the time from POST
(`pending`) until the client polls a resolved status. It's the only script that
exercises `GET /reservations/{id}`. Reports an `e2e_resolve_ms` trend (with p95).
Uses `K6_VUS` / `K6_DURATION` plus `POLL_INTERVAL` (default `0.1`s, which bounds the
measurement resolution). Seed plenty of seats (`initial_seats=100000`) so latency
isn't truncated by `sold_out`.

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
STAGES='[{"duration":"2m","target":200},{"duration":"3m","target":800},{"duration":"1m","target":0}]' \
  scripts/run-gcp-load-test.sh dynamic_load
```
