import math
import os
import json
from uuid import uuid4

import redis
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from .rate_limiter import RateLimiter, RATE_LIMIT_ENABLED
from .redis_keys import (
    booking_queue_key,
    reservation_event_key,
    reservation_status_key,
    reservation_user_key,
)

app = FastAPI()

redis_client = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=6379,
    decode_responses=True,
)

rate_limiter = RateLimiter(redis_client) if RATE_LIMIT_ENABLED else None


class BookingRequest(BaseModel):
    user_id: str


@app.get("/")
def root():
    return {"status": "running"}


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.get("/redis-test")
def redis_test():
    count = redis_client.incr("test_counter")

    return {
        "message": "Redis works",
        "counter": count,
    }


@app.post("/events/{event_id}/book")
def book_event(event_id: int, booking_request: BookingRequest):
    if rate_limiter is not None:
        allowed, _remaining, retry_after_ms = rate_limiter.check(booking_request.user_id)
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail="Rate limit exceeded",
                headers={"Retry-After": str(math.ceil(retry_after_ms / 1000))},
            )

    reservation_id = str(uuid4())

    queue_payload = {
        "reservation_id": reservation_id,
        "event_id": event_id,
        "user_id": booking_request.user_id,
    }
    queue_payload_json = json.dumps(queue_payload)

    pipeline = redis_client.pipeline(transaction=True)
    pipeline.set(reservation_status_key(reservation_id), "pending")
    pipeline.set(reservation_event_key(reservation_id), event_id)
    pipeline.set(reservation_user_key(reservation_id), booking_request.user_id)
    pipeline.rpush(booking_queue_key(event_id), queue_payload_json)
    pipeline.execute()

    return {
        "reservation_id": reservation_id,
        "event_id": event_id,
        "user_id": booking_request.user_id,
        "status": "pending",
    }

@app.get("/reservations/{reservation_id}")
def get_reservation(reservation_id: str):
    reservation_status = redis_client.get(reservation_status_key(reservation_id))
    reservation_event = redis_client.get(reservation_event_key(reservation_id))
    reservation_user = redis_client.get(reservation_user_key(reservation_id))
    if reservation_status is None:
        raise HTTPException(
            status_code=404,
            detail="Reservation not found"
        )
    return {
        "reservation_id": reservation_id,
        "status": reservation_status,
        "event_id": reservation_event,
        "user_id": reservation_user,
    }
