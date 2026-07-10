# Worker Cells

This folder contains the worker-cell runtime and any per-cell coordination artifacts.

Current MVP worker responsibilities:

- consume booking requests from `event:{event_id}:booking_queue`
- parse queued JSON payloads
- call the Lua script in `infrastructure/redis/lua/reserve_atomic.lua`
- update reservation status indirectly through the Lua script
- execute a fixed number of queue slots per interval for the constant-work pattern

Run the worker from the repository root:

```bash
python -m workers.cells.worker
```

Constant-work tuning knobs:

- `WORKER_BATCH_SIZE`
  - number of queue slots processed per cycle
  - default: `100`
- `WORKER_INTERVAL_SECONDS`
  - cycle duration target in seconds
  - default: `1.0`

Example:

```bash
WORKER_BATCH_SIZE=5 WORKER_INTERVAL_SECONDS=2 python -m workers.cells.worker
```
