-- Per-key token-bucket rate limiter (atomic).
--
-- KEYS[1] = bucket key (e.g. ratelimit:user:{user_id})
-- ARGV[1] = capacity       (max tokens / burst size)
-- ARGV[2] = refill_rate    (tokens per second, may be fractional)
-- ARGV[3] = requested      (tokens to consume, usually 1)
--
-- Returns { allowed (1|0), tokens_remaining (floored int), retry_after_ms }

local key         = KEYS[1]
local capacity    = tonumber(ARGV[1])
local refill_rate = tonumber(ARGV[2])
local requested   = tonumber(ARGV[3])

-- Single clock source: the Redis server time, so all API replicas agree.
local t = redis.call("TIME")
local now_ms = (tonumber(t[1]) * 1000) + math.floor(tonumber(t[2]) / 1000)

local bucket = redis.call("HMGET", key, "tokens", "ts")
local tokens = tonumber(bucket[1])
local ts = tonumber(bucket[2])

-- First request for this key: start with a full bucket.
if tokens == nil then
    tokens = capacity
    ts = now_ms
end

-- Refill based on elapsed time, capped at capacity.
local elapsed_ms = now_ms - ts
if elapsed_ms < 0 then
    elapsed_ms = 0
end
tokens = math.min(capacity, tokens + (elapsed_ms / 1000.0) * refill_rate)

local allowed = 0
local retry_after_ms = 0
if tokens >= requested then
    tokens = tokens - requested
    allowed = 1
else
    -- Time until enough tokens have refilled to satisfy the request.
    local deficit = requested - tokens
    retry_after_ms = math.ceil((deficit / refill_rate) * 1000)
end

redis.call("HSET", key, "tokens", tokens, "ts", now_ms)

-- Let idle buckets expire once they would have fully refilled (plus a buffer).
local ttl_ms = math.ceil((capacity / refill_rate) * 1000) + 1000
redis.call("PEXPIRE", key, ttl_ms)

return { allowed, math.floor(tokens), retry_after_ms }
