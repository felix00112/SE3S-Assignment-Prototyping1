# Redis Reservation State

This folder groups Redis reservation-state artifacts such as seat counters, reserved-user sets, and reservation status keys.

Why this folder exists:

- the reservation state is shared across API, worker, and Lua script
- this folder documents the Redis keys that make up that shared state
- it acts as the architectural contract for how reservation data is stored

This keeps the state model visible in one place instead of burying it only inside Python and Lua code.

Current key contract:

- `event:{event_id}:seats_available`
- `event:{event_id}:reserved_users`
- `reservation:{reservation_id}:status`
- `reservation:{reservation_id}:event_id`
- `reservation:{reservation_id}:user_id`

Detailed reservation statuses:

- `pending`: request accepted by the API and added to the queue
- `reserved`: worker + Lua script successfully reserved a seat
- `sold_out`: no seats were left when the worker processed the request
- `duplicate`: the same user already has a reservation for that event
- `event_not_found`: the event seat counter was missing in Redis

Ownership boundary:

- API writes initial reservation metadata and sets `pending`
- Lua script decides the booking outcome and updates only `reservation:{reservation_id}:status`
