"""
API-side compatibility wrapper around the shared Redis key contract.

The actual source of truth lives in `shared.redis_keys` so the API and worker
use the same naming scheme. This wrapper keeps imports inside the API package
simple while re-exporting the shared helpers.
"""

from shared.redis_keys import (
    DEFAULT_EVENT_ID,
    booking_queue_key,
    event_key,
    event_seats_available_key,
    event_seats_total_key,
    rate_limit_user_key,
    reservation_event_key,
    reservation_key,
    reservation_status_key,
    reservation_user_key,
    reserved_users_key,
)
