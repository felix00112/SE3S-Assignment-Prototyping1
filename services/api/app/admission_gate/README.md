# Admission Gate

Queue-capacity backpressure for the booking API. It rejects a booking when the
booking queue is already at capacity, so the backlog cannot grow unbounded under
flash-sale load. It runs in the API request path **after** the rate limiter and
**at** the enqueue step.

## Contract

- Rejected requests get HTTP `503 Service Unavailable` with a `Retry-After`
  header.
- The queue-length check and the enqueue happen together in an atomic Lua script
  ([`infrastructure/redis/admission-gate/admit_and_enqueue.lua`](../../../../infrastructure/redis/admission-gate/admit_and_enqueue.lua)):
  if `LLEN(queue) >= max` it returns `{0, qlen}` and writes nothing; otherwise it
  sets the `reservation:{id}:*` metadata, `RPUSH`es the payload, and returns
  `{1, new_qlen}`. Because the check and writes are one script, concurrent
  requests cannot overshoot the limit.

## Configuration (API env vars)

- `ADMISSION_MAX_QUEUE_LENGTH` — max pending items in the booking queue
  (default `100`).
- `ADMISSION_RETRY_AFTER_SECONDS` — value of the `Retry-After` header on `503`
  (default `1`).
- `ADMISSION_ENABLED` — set `false`/`0`/`no` to bypass the gate and fall back to
  the unbounded enqueue path. Default enabled.
- `ADMISSION_LUA_PATH` — override the script location if needed.

## Where the code lives

- Script: `infrastructure/redis/admission-gate/admit_and_enqueue.lua`
- API integration: `services/api/app/admission_gate/__init__.py`, applied in
  `book_event` in `services/api/app/main.py`

## Note

This gate only bounds the queue length. It is distinct from the per-user
**rate limiter** (`infrastructure/redis/rate-limiter/`), which throttles how fast
a single user may submit requests and rejects with `429`.
