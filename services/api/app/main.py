import os
import psycopg2
import redis
from fastapi import FastAPI
from pydantic import BaseModel
import psycopg2.extras

app = FastAPI()

redis_client = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=6379,
    decode_responses=True
)


class EventCreate(BaseModel):
    event_type: str
    payload: dict | None = None


def get_connection():
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        database=os.getenv("POSTGRES_DB", "scaling_app"),
        user=os.getenv("POSTGRES_USER", "postgres"),
        password=os.getenv("POSTGRES_PASSWORD", "postgres"),
    )


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
        "counter": count
    }

@app.post("/events")
def create_event(event: EventCreate):
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        INSERT INTO app_events (event_type, payload)
        VALUES (%s, %s)
        RETURNING id, event_type, payload, created_at;
        """,
        (event.event_type, psycopg2.extras.Json(event.payload)),
    )

    row = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()

    return {
        "id": row[0],
        "event_type": row[1],
        "payload": row[2],
        "created_at": row[3],
    }


@app.get("/events")
def get_events():
    conn = get_connection()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT id, event_type, payload, created_at
        FROM app_events
        ORDER BY id DESC;
        """
    )

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return [
        {
            "id": row[0],
            "event_type": row[1],
            "payload": row[2],
            "created_at": row[3],
        }
        for row in rows
    ]