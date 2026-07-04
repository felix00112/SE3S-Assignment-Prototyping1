import json
import os
import sys
from pathlib import Path

import redis

from shared.redis_keys import (
    booking_queue_key,
    event_seats_available_key,
    reservation_status_key,
    reserved_users_key,
)


def redis_client() -> redis.Redis:
    return redis.Redis(
        host=os.getenv("REDIS_HOST", "localhost"),
        port=int(os.getenv("REDIS_PORT", "6379")),
        db=int(os.getenv("REDIS_DB", "0")),
        decode_responses=True,
    )


DEFAULT_LUA_SCRIPT_PATH = (
    Path(__file__).resolve().parents[2] / "infrastructure" / "redis" / "lua" / "reserve_atomic.lua"
)
LUA_SCRIPT_PATH = Path(os.getenv("RESERVE_TICKET_LUA_PATH", DEFAULT_LUA_SCRIPT_PATH))


def load_reserve_ticket_script(redis_client):
    script = LUA_SCRIPT_PATH.read_text()
    return redis_client.register_script(script)


def main() -> int:
    event_id = int(os.getenv("EVENT_ID", "1"))
    queue_key = os.getenv("BOOKING_QUEUE_KEY", booking_queue_key(event_id))
    timeout_seconds = int(os.getenv("QUEUE_POP_TIMEOUT_SECONDS", "5"))

    client = redis_client()
    reserve_ticket = load_reserve_ticket_script(client)
    print(f"Worker listening on {queue_key}")

    while True:
        try:
            result = client.blpop(queue_key, timeout=timeout_seconds)
        except redis.RedisError as exc:
            print(f"Could not read from Redis: {exc}", file=sys.stderr)
            return 1

        if result is None:
            queue_length = client.llen(queue_key)
            print(f"No item found in {queue_key}. Queue length: {queue_length}")
            continue

        _, item = result

        try:
            reservation = json.loads(item)
        except json.JSONDecodeError:
            print(f"Invalid queue item: {item}", file=sys.stderr)
            continue

        reservation_id = reservation.get("reservation_id")
        if not reservation_id:
            print(f"Queue item has no reservation_id: {reservation}", file=sys.stderr)
            continue

        reservation_event_id = int(reservation.get("event_id", event_id))
        user_id = reservation.get("user_id")
        if not user_id:
            print(f"Queue item has no user_id: {reservation}", file=sys.stderr)
            continue

        status = reserve_ticket(
            keys=[
                event_seats_available_key(reservation_event_id),
                reserved_users_key(reservation_event_id),
                reservation_status_key(reservation_id),
            ],
            args=[user_id],
        )
        reservation["status"] = status.lower()

        print(json.dumps(reservation, indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
