"""Redis-backed admission gate for the booking API.

Rejects bookings when the booking queue is already at capacity, so the backlog
cannot grow unbounded under load. The queue-length check and the enqueue are
performed together in an atomic Lua script
(`infrastructure/redis/admission-gate/admit_and_enqueue.lua`), so concurrent
requests cannot overshoot the limit via a check-then-act race.

This is the queue-capacity gate only; it runs after the rate limiter in the API
request path.
"""

import os
from pathlib import Path

from ..redis_keys import (
    booking_queue_key,
    reservation_event_key,
    reservation_status_key,
    reservation_user_key,
)

DEFAULT_LUA_SCRIPT_PATH = (
    Path(__file__).resolve().parents[4]
    / "infrastructure"
    / "redis"
    / "admission-gate"
    / "admit_and_enqueue.lua"
)
LUA_SCRIPT_PATH = Path(os.getenv("ADMISSION_LUA_PATH", DEFAULT_LUA_SCRIPT_PATH))

# Maximum number of pending items allowed in the booking queue.
MAX_QUEUE_LENGTH = int(os.getenv("ADMISSION_MAX_QUEUE_LENGTH", "100"))

# Static hint sent to rejected clients (seconds).
ADMISSION_RETRY_AFTER_SECONDS = int(os.getenv("ADMISSION_RETRY_AFTER_SECONDS", "1"))

# Allow disabling the gate entirely (falls back to the unbounded enqueue path).
ADMISSION_ENABLED = os.getenv("ADMISSION_ENABLED", "true").strip().lower() not in {
    "0",
    "false",
    "no",
}


class AdmissionGate:
    """Atomic queue-capacity gate that also performs the enqueue."""

    def __init__(self, client, max_queue_length: int = MAX_QUEUE_LENGTH):
        self._script = client.register_script(LUA_SCRIPT_PATH.read_text())
        self._max_queue_length = max_queue_length

    def admit(self, reservation_id: str, event_id: int, user_id: str, payload_json: str):
        """Try to admit and enqueue a booking.

        Returns (admitted, queue_length).
        """
        admitted, queue_length = self._script(
            keys=[
                booking_queue_key(event_id),
                reservation_status_key(reservation_id),
                reservation_event_key(reservation_id),
                reservation_user_key(reservation_id),
            ],
            args=[self._max_queue_length, event_id, user_id, payload_json],
        )
        return bool(admitted), int(queue_length)
