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

`baseline_scaling.js` is the **open-loop scaling baseline** for the 1/3/5 comparison.
It uses a `ramping-arrival-rate` executor: it **ramps the offered load from
`BASELINE_START_RATE` up to `BASELINE_RATE`** over `BASELINE_DURATION`, regardless of
how fast the cluster responds (no coordinated omission; every cluster sees the same
offered curve). Fresh user per request, and `503` is marked an expected status so
admission shedding doesn't count as a transport failure. **One run per cluster** — no
rate sweep: each run reveals that cluster's ceiling as the point where accepted/s
plateaus while 503s, latency, and **dropped iterations** climb. That knee rises with
node count. Read it from the raw CSV (accepted/s over time). Knobs: `BASELINE_RATE`
(peak), `BASELINE_START_RATE`, `BASELINE_DURATION`, `BASELINE_PREALLOCATED_VUS`,
`BASELINE_MAX_VUS`.

> Control this one with `BASELINE_*`, **not** `K6_VUS` / `K6_DURATION`. Those are
> reserved by k6 and, if set, replace the whole `scenarios` block with a single-VU
> closed loop — silently turning it back into a broken closed-loop test.

`constant_load.js` uses `K6_VUS` and `K6_DURATION`.

`baseline_scaling.js` is the recommended **requirement 2 baseline**. It uses a
**constant arrival rate** with a **fresh user_id per request**, so each 1 / 3 / 5 node
deployment sees the same offered load and the per-user rate limiter does not dominate
the result. It accepts `503` as expected overload shedding. Override it with:

```bash
BASELINE_RATE=300
BASELINE_TIME_UNIT=1s
BASELINE_PREALLOCATED_VUS=400
BASELINE_MAX_VUS=1200
K6_DURATION=1m
```

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

`realistic_load.js` models **real users** rather than flat-out bots: each VU is one
user (`user-<VU>`) that makes a booking attempt, then **pauses (`THINK_TIME`, default
1s, with jitter)** before the next. The think time keeps each VU idle most of the time,
so it adds almost nothing to concurrency — a VU here is ~100x lighter than a no-sleep
`constant_load` VU. That means **`K6_VUS` maps to concurrent users**: run thousands to
get thousands of distinct users *safely*. At ~1 req/s per user the rate limiter mostly
stays quiet (realistic users aren't throttled). Knobs: `K6_VUS`, `K6_DURATION`,
`THINK_TIME`.

`rate_limit_load.js` also uses `K6_VUS` and `K6_DURATION`, but assigns a **stable
per-VU `user_id`** (`rl-user-<VU>`) instead of a fresh UUID per request. That means
each virtual user repeatedly books as the same user, so requests actually trip the
per-user rate limiter. It reports a `throttled_requests` rate (the share of
responses that came back `429`); `constant_load.js` / `dynamic_load.js` generate a
unique user per request and therefore only measure throughput, never throttling.

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
scripts/run-gcp-load-test.sh baseline_scaling
scripts/run-gcp-load-test.sh constant_load
scripts/run-gcp-load-test.sh dynamic_load
```

Example baseline scaling run:

```bash
BASELINE_RATE=300 K6_DURATION=1m scripts/run-gcp-load-test.sh baseline_scaling
```

Example with custom load shape:

```bash
K6_VUS=100 K6_DURATION=5m scripts/run-gcp-load-test.sh constant_load
STAGES='[{"duration":"2m","target":200},{"duration":"3m","target":800},{"duration":"1m","target":0}]' \
  scripts/run-gcp-load-test.sh dynamic_load
```
