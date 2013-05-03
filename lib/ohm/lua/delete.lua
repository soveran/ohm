local model       = cmsgpack.unpack(ARGV[1])
local uniques     = cmsgpack.unpack(ARGV[2])
local tracked     = cmsgpack.unpack(ARGV[3])

local function remove_indices(model)
  local memo = model.key .. ":_indices"
  local existing = redis.call("SMEMBERS", memo)

  for _, key in ipairs(existing) do
    redis.call("SREM", key, model.id)
    redis.call("SREM", memo, key)
  end
end

local function remove_uniques(model, uniques)
  local memo = model.key .. ":_uniques"

  for field, _ in pairs(uniques) do
    local key = model.name .. ":uniques:" .. field

    redis.call("HDEL", key, redis.call("HGET", memo, key))
    redis.call("HDEL", memo, key)
  end
end

local function remove_tracked(model, tracked)
  for _, tracked_key in ipairs(tracked) do
    local key = model.key .. ":" .. tracked_key

    redis.call("DEL", key)
  end
end

local function delete(model)
  local keys = {
    model.key .. ":counters",
    model.key .. ":_indices",
    model.key .. ":_uniques",
    model.key
  }

  redis.call("SREM", model.name .. ":all", model.id)
  redis.call("DEL", unpack(keys))
end

remove_indices(model)
remove_uniques(model, uniques)
remove_tracked(model, tracked)
delete(model)

return model.id
