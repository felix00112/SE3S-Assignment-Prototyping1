# Booking Queue

The booking queue is a Redis-backed buffer between the synchronous API request path and the asynchronous reservation decision.

## Purpose

- absorb flash-sale spikes without making the booking endpoint do all work synchronously
- decouple request acceptance from final reservation resolution
- provide a clear producer/consumer contract between API and worker

## Current Redis Key

- `event:{event_id}:booking_queue`

## Current Queue Payload

```json
{
  "reservation_id": "uuid",
  "event_id": 1,
  "user_id": "user-123"
}
```

## Responsibility Split

- the API enqueues booking requests
- the worker consumes queue items
- the worker invokes the Redis Lua script that decides the final booking outcome

## Implementation Note

The queue is documented here because its behavior is architectural, while the executable queue logic itself lives in:

- `services/api/`
- `workers/cells/`

If queue-specific scripts or infrastructure are added later, they can still live under `infrastructure/redis/`.
