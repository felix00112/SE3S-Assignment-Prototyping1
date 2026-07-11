local seats_available_key = KEYS[1]
local reserved_users_key = KEYS[2]
local dummy_slots_key = KEYS[3]

local seats_raw = redis.call("GET", seats_available_key)
if not seats_raw then
    return "EVENT_NOT_FOUND"
end

redis.call("SCARD", reserved_users_key)
redis.call("INCR", dummy_slots_key)

return "DUMMY"
