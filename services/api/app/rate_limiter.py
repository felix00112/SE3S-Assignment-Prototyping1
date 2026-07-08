"""Redis-backed per-user token-bucket rate limiter for the booking API.

The atomic counting logic lives in the Lua script under
`infrastructure/redis/rate-limiter/token_bucket.lua`, mirroring how the booking
decision lives in `reserve_atomic.lua`. This module only loads that script and
exposes a small `check()` helper used by the API request path.
"""

import os
from pathlib import Path

from .redis_keys import rate_limit_user_key

DEFAULT_LUA_SCRIPT_PATH = (
    Path(__file__).resolve().parents[3]
    / "infrastructure"
    / "redis"
    / "rate-limiter"
    / "token_bucket.lua"
)
LUA_SCRIPT_PATH = Path(os.getenv("RATE_LIMIT_LUA_PATH", DEFAULT_LUA_SCRIPT_PATH))

# Burst size (max tokens) and sustained refill rate (tokens per second).
CAPACITY = float(os.getenv("RATE_LIMIT_CAPACITY", "5"))
REFILL_RATE = float(os.getenv("RATE_LIMIT_REFILL_RATE", "1"))

# Allow disabling the limiter entirely (e.g. for load-testing the raw path).
RATE_LIMIT_ENABLED = os.getenv("RATE_LIMIT_ENABLED", "true").strip().lower() not in {
    "0",
    "false",
    "no",
}


class RateLimiter:
    """Per-user token bucket backed by an atomic Redis Lua script."""

    def __init__(self, client, capacity: float = CAPACITY, refill_rate: float = REFILL_RATE):
        self._script = client.register_script(LUA_SCRIPT_PATH.read_text())
        self._capacity = capacity
        self._refill_rate = refill_rate

    def check(self, user_id: str, tokens: int = 1):
        """Consume `tokens` for `user_id`.

        Returns (allowed, tokens_remaining, retry_after_ms).
        """
        allowed, remaining, retry_after_ms = self._script(
            keys=[rate_limit_user_key(user_id)],
            args=[self._capacity, self._refill_rate, tokens],
        )
        return bool(allowed), int(remaining), int(retry_after_ms)
