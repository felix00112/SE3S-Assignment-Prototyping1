# Redis Booking Queue

This folder contains queue-related Redis artifacts and documentation.

Why this folder exists:

- the actual queue operations are implemented in the API and the worker
- this folder is the architectural home of the booking queue concept
- it documents the queue key, payload format, and producer/consumer responsibilities

So this folder is intentionally lightweight. It is not supposed to contain lots of extra code unless queue-specific scripts or utilities are added later.

Current queue key:

- `event:{event_id}:booking_queue`

Current queue payload:

```json
{
  "reservation_id": "uuid",
  "event_id": 1,
  "user_id": "user-123"
}
```

Queue responsibility:

- The API enqueues booking requests
- The worker consumes them with `BLPOP`
- The worker calls the Lua script to decide whether the request becomes `reserved`, `sold_out`, `duplicate`, or `event_not_found`
