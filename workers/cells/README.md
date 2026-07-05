# Worker Cells

This folder contains the worker-cell runtime and any per-cell coordination artifacts.

Current MVP worker responsibilities:

- consume booking requests from `event:{event_id}:booking_queue`
- parse queued JSON payloads
- call the Lua script in `infrastructure/redis/lua/reserve_atomic.lua`
- update reservation status indirectly through the Lua script

Run the worker from the repository root:

```bash
python -m workers.cells.worker
```
