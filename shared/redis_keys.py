DEFAULT_EVENT_ID = 1


def event_key(event_id: int, name: str) -> str:
    return f"event:{event_id}:{name}"


def reservation_key(reservation_id: str, name: str) -> str:
    return f"reservation:{reservation_id}:{name}"


def booking_queue_key(event_id: int = DEFAULT_EVENT_ID) -> str:
    return event_key(event_id, "booking_queue")


def event_seats_total_key(event_id: int = DEFAULT_EVENT_ID) -> str:
    return event_key(event_id, "seats_total")


def event_seats_available_key(event_id: int = DEFAULT_EVENT_ID) -> str:
    return event_key(event_id, "seats_available")


def reserved_users_key(event_id: int = DEFAULT_EVENT_ID) -> str:
    return event_key(event_id, "reserved_users")


def dummy_slots_key(event_id: int = DEFAULT_EVENT_ID) -> str:
    return event_key(event_id, "dummy_slots")


def dummy_reserved_users_key(event_id: int = DEFAULT_EVENT_ID) -> str:
    return event_key(event_id, "dummy_reserved_users")


def dummy_status_key(event_id: int = DEFAULT_EVENT_ID) -> str:
    return event_key(event_id, "dummy_status")


def reservation_status_key(reservation_id: str) -> str:
    return reservation_key(reservation_id, "status")


def reservation_event_key(reservation_id: str) -> str:
    return reservation_key(reservation_id, "event_id")


def reservation_user_key(reservation_id: str) -> str:
    return reservation_key(reservation_id, "user_id")


def rate_limit_user_key(user_id: str) -> str:
    return f"ratelimit:user:{user_id}"
