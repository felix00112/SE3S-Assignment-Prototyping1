import json
import os
import sys

import redis

from shared.redis_keys import booking_queue_key, reservation_status_key


def redis_client() -> redis.Redis:
    return redis.Redis(
        host=os.getenv("REDIS_HOST", "localhost"),
        port=int(os.getenv("REDIS_PORT", "6379")),
        db=int(os.getenv("REDIS_DB", "0")),
        decode_responses=True,
    )


def main() -> int:
    event_id = int(os.getenv("EVENT_ID", "1"))
    queue_key = os.getenv("BOOKING_QUEUE_KEY", booking_queue_key(event_id))
    timeout_seconds = int(os.getenv("QUEUE_POP_TIMEOUT_SECONDS", "5"))

    client = redis_client()
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

        status_key = reservation_status_key(reservation_id)
        client.set(status_key, "confirmed")
        reservation["status"] = "confirmed"

        print(json.dumps(reservation, indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
