# Target Folder Structure

The repository is now organized around the booking-system architecture:

- `gateway/nginx/` for the load balancer layer
- `services/api/` for the FastAPI application and status/admission-gate areas
- `workers/cells/` for worker-cell processing
- `workers/cleanup/` for the optional cleanup worker
- `infrastructure/redis/` for rate limiting, booking queue, Lua script, and reservation state
- `tests/k6/` for primary load tests
- `tests/locust/` for optional alternative load tests

How to interpret this split:

- `services/` and `workers/` contain executable application code
- `infrastructure/redis/` contains Redis-specific infrastructure artifacts and architectural contracts

For the current MVP specifically:

- booking queue logic is executed by the API and the worker
- `infrastructure/redis/booking-queue/` documents the queue contract and gives that architectural piece a clear place in the repo
- reservation state is read and written by the API, worker, and Lua script
- `infrastructure/redis/reservation-state/` documents the Redis state model
- the atomic booking decision lives directly in `infrastructure/redis/lua/reserve_atomic.lua`

The goal is clarity, not extra layers. The infrastructure folders exist so someone can understand the system shape quickly without hunting through code first.
