-- Atomic admission gate + enqueue.
--
-- Rejects the booking when the queue is already at capacity; otherwise writes
-- the reservation metadata and enqueues the payload. Doing the length check and
-- the writes in one script removes the check-then-act race, so concurrent
-- requests cannot overshoot the configured limit.
--
-- KEYS[1] = booking queue key
-- KEYS[2] = reservation status key
-- KEYS[3] = reservation event key
-- KEYS[4] = reservation user key
-- ARGV[1] = max queue length
-- ARGV[2] = event_id
-- ARGV[3] = user_id
-- ARGV[4] = queue payload (JSON)
--
-- Returns { admitted (1|0), queue_length }

local queue_key  = KEYS[1]
local status_key = KEYS[2]
local event_key  = KEYS[3]
local user_key   = KEYS[4]

local max_len  = tonumber(ARGV[1])
local event_id = ARGV[2]
local user_id  = ARGV[3]
local payload  = ARGV[4]

local qlen = redis.call("LLEN", queue_key)

if qlen >= max_len then
    return { 0, qlen }
end

redis.call("SET", status_key, "pending")
redis.call("SET", event_key, event_id)
redis.call("SET", user_key, user_id)
qlen = redis.call("RPUSH", queue_key, payload)

return { 1, qlen }
