import os

import redis
from fastapi import FastAPI

app = FastAPI()

redis_client = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=6379,
    decode_responses=True,
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
        "counter": count,
    }
