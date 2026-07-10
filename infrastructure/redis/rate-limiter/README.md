# Redis Rate Limiter

Per-user token-bucket rate limiter that sits in the API request path, before a
booking is enqueued. It throttles how fast a single `user_id` can submit booking
requests during a flash sale; requests over budget are rejected with HTTP `429`.

## Contract

- Key: `ratelimit:user:{user_id}` — a Redis hash holding `tokens` (remaining,
  fractional) and `ts` (last-refill time in ms, from the Redis server clock).
- Atomic logic: [`token_bucket.lua`](token_bucket.lua). Each request refills the
  bucket based on elapsed time (capped at capacity), then consumes one token if
  available. Idle buckets expire via `PEXPIRE`.
- The script uses `redis.call("TIME")` as a single clock source so multiple API
  replicas agree on refill timing.

## Configuration (API env vars)

- `RATE_LIMIT_CAPACITY` — burst size / max tokens (default `5`).
- `RATE_LIMIT_REFILL_RATE` — sustained tokens per second, may be fractional
  (default `1`).
- `RATE_LIMIT_ENABLED` — set to `false`/`0`/`no` to bypass the limiter (e.g. to
  load-test the raw path). Default enabled.
- `RATE_LIMIT_LUA_PATH` — override the script location if needed.

Defaults mean a user may burst 5 requests, then ~1 request/second sustained.

## Where the code lives

- Script: `infrastructure/redis/rate-limiter/token_bucket.lua`
- API integration: `services/api/app/rate_limiter.py`, applied at the top of
  `book_event` in `services/api/app/main.py`
- Key helper: `rate_limit_user_key()` in `shared/redis_keys.py`

## Note

This is the request-rate limiter only. The **admission gate** (rejecting when the
booking queue is full) is a separate, still-unimplemented piece — see
`services/api/app/admission_gate/`.
