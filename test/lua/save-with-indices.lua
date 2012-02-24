local key     = KEYS[1]
local all     = KEYS[2]
local indices = KEYS[3]
local id      = string.match(key, "(%w+)$")

local _indices = key .. ":_indices"

local save = function (atts)
  redis.call("DEL", key)
  redis.call("HMSET", key, unpack(atts))
  redis.call("SADD", all, id)
end

local _delete_indices = function()
  for _, v in pairs(redis.call("SMEMBERS", _indices)) do
    redis.call("SREM", v, id)
  end
  redis.call("DEL", _indices)
end

local _save_indices = function()
  for _, att in pairs(redis.call("SMEMBERS", indices)) do
    local val = redis.call("HGET", key, att)
    -- TODO: should be base64(val), and think about how to pass User:%s:%s
    local index = string.format("User:%s:%s", att, val)
   
    redis.call("SADD", index, id)
    redis.call("SADD", _indices, index)
  end
end

_delete_indices()
save(ARGV)
_save_indices()

return "OK"
