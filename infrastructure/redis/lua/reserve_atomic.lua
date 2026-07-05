local seats_available_key = KEYS[1]
local reserved_users_key = KEYS[2]
local reservation_status_key = KEYS[3]

local user_id = ARGV[1]

local seats_raw = redis.call("GET", seats_available_key)

if not seats_raw then
    redis.call("SET", reservation_status_key, "event_not_found")
    return "EVENT_NOT_FOUND"
end

local seats_available = tonumber(seats_raw)

if redis.call("SISMEMBER", reserved_users_key, user_id) == 1 then
    redis.call("SET", reservation_status_key, "duplicate")
    return "DUPLICATE"
end

if seats_available <= 0 then
    redis.call("SET", reservation_status_key, "sold_out")
    return "SOLD_OUT"
end

redis.call("DECR", seats_available_key)
redis.call("SADD", reserved_users_key, user_id)

redis.call("SET", reservation_status_key, "reserved")

return "RESERVED"
