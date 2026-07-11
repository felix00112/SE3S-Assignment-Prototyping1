local seats_available_key = KEYS[1]
local dummy_reserved_users_key = KEYS[2]
local dummy_status_key = KEYS[3]
local dummy_slots_key = KEYS[4]

local dummy_user_id = ARGV[1]

local seats_raw = redis.call("GET", seats_available_key)
if not seats_raw then
    redis.call("SET", dummy_status_key, "event_not_found")
    return "EVENT_NOT_FOUND"
end

local seats_available = tonumber(seats_raw)

if redis.call("SISMEMBER", dummy_reserved_users_key, dummy_user_id) == 1 then
    redis.call("SET", dummy_status_key, "duplicate")
    redis.call("INCR", dummy_slots_key)
    redis.call("SREM", dummy_reserved_users_key, dummy_user_id)
    return "DUMMY_DUPLICATE"
end

if seats_available <= 0 then
    redis.call("SET", dummy_status_key, "sold_out")
    redis.call("INCR", dummy_slots_key)
    return "DUMMY_SOLD_OUT"
end

redis.call("INCR", dummy_slots_key)
redis.call("SADD", dummy_reserved_users_key, dummy_user_id)
redis.call("SET", dummy_status_key, "reserved")
redis.call("SREM", dummy_reserved_users_key, dummy_user_id)

return "DUMMY"
