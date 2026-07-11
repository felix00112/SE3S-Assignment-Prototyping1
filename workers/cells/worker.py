import json
import os
import sys
import time
from pathlib import Path

import redis

from shared.redis_keys import (
    booking_queue_key,
    dummy_slots_key,
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
DEFAULT_DUMMY_LUA_SCRIPT_PATH = (
    Path(__file__).resolve().parents[2] / "infrastructure" / "redis" / "lua" / "dummy_slot.lua"
)
DUMMY_LUA_SCRIPT_PATH = Path(os.getenv("DUMMY_SLOT_LUA_PATH", DEFAULT_DUMMY_LUA_SCRIPT_PATH))


def load_reserve_ticket_script(redis_client):
    script = LUA_SCRIPT_PATH.read_text()
    return redis_client.register_script(script)


def load_dummy_slot_script(redis_client):
    script = DUMMY_LUA_SCRIPT_PATH.read_text()
    return redis_client.register_script(script)


def process_real_reservation(reserve_ticket, reservation: dict, default_event_id: int) -> str | None:
    reservation_id = reservation.get("reservation_id")
    if not reservation_id:
        print(f"Queue item has no reservation_id: {reservation}", file=sys.stderr)
        return None

    user_id = reservation.get("user_id")
    if not user_id:
        print(f"Queue item has no user_id: {reservation}", file=sys.stderr)
        return None

    reservation_event_id = int(reservation.get("event_id", default_event_id))
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
    return reservation["status"]


def process_dummy_slot(run_dummy_slot, event_id: int) -> None:
    run_dummy_slot(
        keys=[
            event_seats_available_key(event_id),
            reserved_users_key(event_id),
            dummy_slots_key(event_id),
        ]
    )


def process_queue_slot(
    client: redis.Redis,
    queue_key: str,
    reserve_ticket,
    run_dummy_slot,
    default_event_id: int,
    synthetic_dummy_mode: bool,
) -> bool:
    try:
        item = client.lpop(queue_key)
    except redis.RedisError as exc:
        print(f"Could not read from Redis: {exc}", file=sys.stderr)
        raise

    if item is None:
        if synthetic_dummy_mode:
            process_dummy_slot(run_dummy_slot, default_event_id)
        return False

    try:
        reservation = json.loads(item)
    except json.JSONDecodeError:
        print(f"Invalid queue item: {item}", file=sys.stderr)
        return False

    return process_real_reservation(reserve_ticket, reservation, default_event_id) is not None


def main() -> int:
    event_id = int(os.getenv("EVENT_ID", "1"))
    queue_key = os.getenv("BOOKING_QUEUE_KEY", booking_queue_key(event_id))
    batch_size = int(os.getenv("WORKER_BATCH_SIZE", "100"))
    interval_seconds = float(os.getenv("WORKER_INTERVAL_SECONDS", "1.0"))
    synthetic_dummy_mode = os.getenv("WORKER_SYNTHETIC_DUMMY_MODE", "0") == "1"

    client = redis_client()
    reserve_ticket = load_reserve_ticket_script(client)
    run_dummy_slot = load_dummy_slot_script(client)
    print(
        f"Worker listening on {queue_key} with {batch_size} slots every {interval_seconds:.3f}s "
        f"(synthetic_dummy_mode={synthetic_dummy_mode})"
    )

    while True:
        cycle_started = time.monotonic()
        real_jobs = 0
        dummy_jobs = 0

        try:
            for _ in range(batch_size):
                if process_queue_slot(
                    client,
                    queue_key,
                    reserve_ticket,
                    run_dummy_slot,
                    event_id,
                    synthetic_dummy_mode,
                ):
                    real_jobs += 1
                else:
                    dummy_jobs += 1
        except redis.RedisError as exc:
            print(f"Worker cycle failed: {exc}", file=sys.stderr)
            return 1

        try:
            queue_length = client.llen(queue_key)
        except redis.RedisError as exc:
            print(f"Could not read queue length from Redis: {exc}", file=sys.stderr)
            return 1

        elapsed = time.monotonic() - cycle_started
        utilization = real_jobs / batch_size if batch_size else 0.0
        print(
            json.dumps(
                {
                    "type": "worker_cycle",
                    "queue_key": queue_key,
                    "batch_size": batch_size,
                    "interval_seconds": interval_seconds,
                    "synthetic_dummy_mode": synthetic_dummy_mode,
                    "real_jobs": real_jobs,
                    "dummy_jobs": dummy_jobs,
                    "utilization": round(utilization, 4),
                    "queue_length": queue_length,
                    "cycle_elapsed_seconds": round(elapsed, 4),
                }
            )
        )

        time.sleep(max(0.0, interval_seconds - elapsed))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
