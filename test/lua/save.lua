local key = KEYS[1]
local all = KEYS[2]
local id  = string.match(key, "(%w+)$")

local save = function (atts)
  redis.call("DEL", key)
  redis.call("HMSET", key, unpack(atts))
  redis.call("SADD", all, id)
end

save(ARGV)

return "OK"
