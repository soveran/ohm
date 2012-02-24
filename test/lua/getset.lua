local key = KEYS[1]
local val = ARGV[1]
local old = redis.call("GET", key)

redis.call("SET", key, val)

return { old, val }
