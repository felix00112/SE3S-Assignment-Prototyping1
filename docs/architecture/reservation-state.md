# Reservation State

The reservation state is the shared Redis data model used by the API, the worker, and the Redis Lua reservation script.

## Purpose

- keep seat inventory and reservation status in a single shared state store
- define the key contract across Python and Lua components
- make the ownership boundary of booking data explicit

## Current Key Contract

- `event:{event_id}:seats_available`
- `event:{event_id}:reserved_users`
- `reservation:{reservation_id}:status`
- `reservation:{reservation_id}:event_id`
- `reservation:{reservation_id}:user_id`

## Detailed Reservation Statuses

- `pending`: request accepted by the API and added to the queue
- `reserved`: worker and Lua script successfully reserved a seat
- `sold_out`: no seats were left when the worker processed the request
- `duplicate`: the same user already has a reservation for that event
- `event_not_found`: the event seat counter was missing in Redis

## Ownership Boundary

- the API writes initial reservation metadata and sets `pending`
- the worker invokes the Lua reservation script
- the Lua script decides the final booking outcome and updates `reservation:{reservation_id}:status`

## Implementation Note

This is documentation for the shared state contract. The executable logic that uses this contract lives in:

- `services/api/`
- `workers/cells/`
- `infrastructure/redis/lua/`
