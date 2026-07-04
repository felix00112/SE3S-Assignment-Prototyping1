# Target Folder Structure

The repository is now organized around the booking-system architecture:

- `gateway/nginx/` for the load balancer layer
- `services/api/` for the FastAPI application and status/admission-gate areas
- `workers/cells/` for worker-cell processing
- `workers/cleanup/` for the optional cleanup worker
- `infrastructure/redis/` for rate limiting, booking queue, Lua script, and reservation state
- `tests/k6/` for primary load tests
- `tests/locust/` for optional alternative load tests
