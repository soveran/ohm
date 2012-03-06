-- COMMAND delete
-- KEYS[1] the namespace, e.g. `User`
-- KEYS[2] the actual Hash key e.g. `User:1`
--         for the case of a new record, we leave this blank.

local namespace  = KEYS[1]
local key        = KEYS[2]
local id         = string.match(key, "(%w+)$")

local model = {
  id          = namespace .. ":id",
  all         = namespace .. ":all",
  uniques     = namespace .. ":uniques",
  indices     = namespace .. ":indices",
  collections = namespace .. ":collections",
  key         = namespace .. ":%s"
}

local meta = {
  uniques     = redis.call("SMEMBERS", model.uniques),
  indices     = redis.call("SMEMBERS", model.indices),
  collections = redis.call("SMEMBERS", model.collections)
}

-- This is mainly used with the generation of an index key,
-- e.g. given nil, for the key User:indices:fname, then the key should be
-- `User:indices:fname:` instead of `User:indices:fname:nil`.
local function str(val)
  if val == nil then
    return ""
  else
    return tostring(val)
  end
end

-- Used to cleanup existing unique values stored.
local function delete_uniques(hash, id)
  for _, att in ipairs(meta.uniques) do
    local key = model.uniques .. ":" .. att
    local val = redis.call("HGET", hash, att)

    redis.call("HDEL", key, val, id)
  end
end

-- This is used to cleanup already existing indices previously saved.
local function delete_indices(hash, id)
  for _, att in ipairs(meta.indices) do
    local val = redis.call("HGET", hash, att)

    if val then
      local key  = model.indices .. ":" .. att .. ":" .. str(val)

      redis.call("SREM", key, id)
    end
  end
end

local function delete_collection(key, list)
  for _, att in ipairs(list) do
    redis.call("DEL", key .. ":" .. att)
  end
end


-- Now comes the easy part: We first cleanup both indices and uniques.
-- It's important that we do this before saving, otherwise the old
-- values of the uniques and indices will be lost.
delete_uniques(key, id)
delete_indices(key, id)

-- Now that we've cleaned up, we can now persist the new attributes.
redis.call("DEL", key)
redis.call("SREM", model.all, id)

delete_collection(key, meta.collections)

-- Permanently deleted, now we can safely return.
return { 200, { "id", id }}
