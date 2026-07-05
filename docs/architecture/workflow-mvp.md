# Workflow MVP

This document describes the currently implemented minimal booking workflow MVP.

## Diagram

Implemented MVP parts are marked with `[MVP]`. Planned-next parts are marked with `[NEXT]`.

```mermaid
flowchart TD
    client["Client / Manual HTTP Tests"] --> api["FastAPI API [MVP]\nPOST /events/{event_id}/book"]
    api --> queue["Redis Booking Queue [MVP]\nevent:{event_id}:booking_queue"]
    queue --> worker["Worker Cell [MVP]\nBLPOP consumer"]
    worker --> lua["Atomic Redis Lua Script [MVP]\nreserve_atomic.lua"]
    lua --> seats["Redis seats_available counter [MVP]"]
    lua --> users["Redis reserved_users set [MVP]"]
    lua --> reservation["Redis reservation state [MVP]\nstatus / event_id / user_id"]
    reservation --> status["Status Endpoint [MVP]\nGET /reservations/{reservation_id}"]

    client --> status

    nginx["Nginx Load Balancer [NEXT]"]
    replicas["FastAPI Replicas [NEXT]"]
    ratelimit["Redis Rate Limiter [NEXT]"]
    gate["Admission Gate [NEXT]"]
    cleanup["Cleanup Worker [optional]"]
    k6["k6 Load Tests [NEXT]"]

    k6 --> nginx
    nginx --> replicas
    replicas --> ratelimit
    ratelimit --> gate
    gate --> queue
    cleanup --> reservation
```

## Scope

- Single prototype event (`event:1`)
- FastAPI request intake
- Redis-backed booking queue
- Worker-based asynchronous processing
- Atomic booking decision via Redis Lua script
- Reservation status lookup endpoint

## Request Flow

1. A client sends `POST /events/{event_id}/book` with a `user_id`
2. The API generates a `reservation_id`
3. The API stores:
   - `reservation:{reservation_id}:status = pending`
   - `reservation:{reservation_id}:event_id = {event_id}`
   - `reservation:{reservation_id}:user_id = {user_id}`
4. The API enqueues a JSON payload into `event:{event_id}:booking_queue`
5. The worker consumes queue items with `BLPOP`
6. The worker calls the Lua script in `infrastructure/redis/lua/reserve_atomic.lua`
7. The Lua script atomically:
   - checks whether the event exists
   - checks whether the user already reserved
   - checks whether seats are still available
   - decrements seat count if possible
   - updates `reservation:{reservation_id}:status`
8. The client polls `GET /reservations/{reservation_id}`

## Detailed Statuses

- `pending`: request accepted and queued
- `reserved`: seat successfully reserved
- `sold_out`: no seats left
- `duplicate`: same user already reserved a seat for this event
- `event_not_found`: seat counter was missing in Redis

## Component Ownership

- API:
  - accepts requests
  - creates reservation metadata
  - enqueues booking jobs
- Worker:
  - consumes queue items
  - invokes Lua script
- Lua script:
  - performs the atomic reservation decision
  - updates only reservation status
- Redis:
  - holds queue, seat counters, reserved-user set, and reservation state

## Why The Redis Folders Exist

The Redis-related folders under `infrastructure/redis/` are intentionally simple:

- `booking-queue/`
  - documents the queue key and payload contract
  - the queue logic itself is executed by the API and worker

- `reservation-state/`
  - documents the shared Redis key model for reservation state
  - this is the contract used by API, worker, and Lua script

- `lua/`
  - contains the atomic Redis-side booking logic

This means the repo separates:

- running code
  - API in `services/api/`
  - worker in `workers/cells/`
- Redis architecture and state contracts
  - `infrastructure/redis/*`

The intention is clarity, not extra abstraction.

## Redis Key Modules

There are two `redis_keys.py` files on purpose:

- `shared/redis_keys.py`
  - this is the source of truth for Redis key naming
  - both the API and the worker should ultimately rely on this module
  - it exists in `shared/` because the key contract is not API-specific

- `services/api/app/redis_keys.py`
  - this is a thin compatibility wrapper for the API package
  - it re-exports the helpers from `shared.redis_keys`
  - it allows API code to keep local imports such as `from .redis_keys import ...`

Why this split exists:

- the worker and the API must agree on exactly the same Redis keys
- keeping the real definitions in `shared/` avoids duplicated string logic
- keeping a wrapper in `services/api/app/` avoids a disruptive refactor of API imports

Practical rule:

- if you change the Redis key structure, update `shared/redis_keys.py`
- treat `services/api/app/redis_keys.py` as a wrapper, not a second source of truth
