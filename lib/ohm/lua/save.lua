local model      = cmsgpack.unpack(ARGV[1])
local attrs      = cmsgpack.unpack(ARGV[2])
local indices    = cmsgpack.unpack(ARGV[3])
local uniques    = cmsgpack.unpack(ARGV[4])

local function save(model, attrs)
  redis.call("SADD", model.name .. ":all", model.id)
  redis.call("DEL", model.key)

  if math.mod(#attrs, 2) == 1 then
    error("Wrong number of attribute/value pairs")
  end

  if #attrs > 0 then
    redis.call("HMSET", model.key, unpack(attrs))
  end
end

local function index(model, indices)
  for field, enum in pairs(indices) do
    for _, val in ipairs(enum) do
      local key = model.name .. ":indices:" .. field .. ":" .. tostring(val)

      redis.call("SADD", model.key .. ":_indices", key)
      redis.call("SADD", key, model.id)
    end
  end
end

local function remove_indices(model)
  local memo = model.key .. ":_indices"
  local existing = redis.call("SMEMBERS", memo)

  for _, key in ipairs(existing) do
    redis.call("SREM", key, model.id)
    redis.call("SREM", memo, key)
  end
end

local function unique(model, uniques)
  for field, value in pairs(uniques) do
    local key = model.name .. ":uniques:" .. field

    redis.call("HSET", model.key .. ":_uniques", key, value)
    redis.call("HSET", key, value, model.id)
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

local function verify(model, uniques)
  local duplicates = {}

  for field, value in pairs(uniques) do
    local key = model.name .. ":uniques:" .. field
    local id = redis.call("HGET", key, tostring(value))

    if id and id ~= tostring(model.id) then
      duplicates[#duplicates + 1] = field
    end
  end

  return duplicates, #duplicates ~= 0
end

local duplicates, err = verify(model, uniques)

if err then
  error("UniqueIndexViolation: " .. duplicates[1])
end

local function convertBooleans(list)
  for index, value in ipairs(list) do
    if type(value) == "boolean" then
      if value then
        list[index] = 1
      else
        list[index] = nil
        list[index - 1] = nil
      end
    end
  end
end

convertBooleans(attrs)

save(model, attrs)

remove_indices(model)
index(model, indices)

remove_uniques(model, uniques)
unique(model, uniques)

return model.id
