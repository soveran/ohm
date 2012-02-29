-- COMMAND save
-- KEYS[1] the namespace, e.g. `User`
-- KEYS[2] (optional) the actual Hash key e.g. `User:1`
--         for the case of a new record, we leave this blank.
--
-- ARGV[1] the flattened attributes of the model. for uniques and
--         indices to work, this should include all the indices
--         and uniques in addition.
--
--         Example:
--
--           attribute: title, tags
--           unique: slug
--           index:  date, title
--
--           expected ARGV[1]:
--           { "title", "...", "tags", "...", "slug", ...", "date", "..." }
--
--           We can skip the title for the index since that has already been
--           specified.
--

local namespace  = KEYS[1]
local key        = KEYS[2]
local attributes = ARGV
local id

if key and key ~= "" then
  -- since there was a key passed, we can extract the ID from the
  -- key, e.g. `User:1` means an ID of 1.
  id = string.match(key, "(%w+)$")
end

local model = {
  id      = namespace .. ":id",
  all     = namespace .. ":all",
  uniques = namespace .. ":uniques",
  indices = namespace .. ":indices"
}

local meta = {
  uniques  = redis.call("SMEMBERS", model.uniques),
  indices  = redis.call("SMEMBERS", model.indices),
}

-- Converts a flattened list to a key-value dictionary.
-- Used to translate the ARGV into a lua table we can easily use.
local function dict(list)
  local ret = {}

  for i = 1, #list, 2 do
    ret[list[i]] = list[i + 1]
  end

  return ret
end

-- Converts a table into a flattened list. Used to translate
-- the table into the final set of parameters we pass to HMSET.
local function list(table)
  local atts = {}

  for k, v in pairs(table) do
    atts[#atts + 1] = k
    atts[#atts + 1] = v
  end

  return atts
end

-- When saving the attributes of the model, we skip the empty strings
-- and nil values so we can also save a bit on space.
function skip_empty(table)
  local ret = {}

  for k, v in pairs(table) do
    if v and v ~= "" then
      ret[k] = v
    end
  end

  return ret
end

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

-- Even before we attempt to save this record, we need to verify
-- that no unique constraints have been violated. If so, we return
-- an error code like so:
--
--   { 500, { "email", "not_unique" }}
local function detect_duplicate(table, id)
  for _, att in ipairs(meta.uniques) do
    local key = model.uniques .. ":" .. att
    local exists = redis.call("HEXISTS", key, table[att])

    -- FIXME: I'm not 100%, but I think this is a bug in the
    -- way the redis lua is implemented. HEXISTS should auto-coerce to
    -- true/false.
    if tonumber(exists) == 1 then
      local val = redis.call("HGET", key, table[att])

      if val ~= tostring(id) then return att end
    end
  end
end

-- Given the namespace `User` and the unique attribute `email` with a
-- value of 'foo@bar.com', and an ID of 1, we store that into a HASH
-- like so:
--
-- HSET User:uniques:email foo@bar.com 1
--
local function save_uniques(table, id)
  for _, att in ipairs(meta.uniques) do
    local key = model.uniques .. ":" .. att

    redis.call("HSET", key, table[att], id)
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

-- Given the namespace `User` and the unique index `fname` with a
-- value of 'John', and an ID of 1, we store that into a SET like so
--
-- SADD User:indices:fname:John 1
--
local function save_indices(table, id)
  for _, att in ipairs(meta.indices) do
    local key = model.indices .. ":" .. att .. ":" .. str(table[att])

    redis.call("SADD", key, id)
  end
end

-- This is used to cleanup already existing indices previously saved.
local function delete_indices(hash, id)
  for _, att in ipairs(meta.indices) do
    local val = redis.call("HGET", hash, att)

    if val then
      local key  = model.indices .. ":" .. att .. ":" .. val

      redis.call("SREM", key, id)
    end
  end
end

-- You can say this is the crux of this script in the sense that
-- these statements persist all the attributes, indices, and uniques
-- passed into ARGV.
local function save(hash, key)
  local atts = list(hash)

  if #atts > 0 then
    redis.call("DEL", key)
    redis.call("HMSET", key, unpack(atts))
  end
end

-- In the future, we probably plan to allow users to hook into scripts
-- on a per model basis. They can tap into `this` and possibly do
-- some manipulations before persisting it finally.
local this = skip_empty(dict(attributes))

-- We try to find any existing duplicates for all of the declared
-- uniques of the model. Ideally you've validated that the entry
-- is already unique even before it reaches this point, but this also
-- serves as the last line of defense, similar to constraints in an RDBMS.
local duplicate = detect_duplicate(this, id)

-- We short-circuit the script if we find any form of unique constraint
-- violation.
if duplicate then
  return { 500, { duplicate, "not_unique" }}
end

-- This is the great differentiator between a new record and an existing
-- one: an existing one should have an ID.
--
-- Given that this is a new record, we have to do a couple of stuff namely:
--
-- 1. Generate a new ID.
-- 2. Reflect that change into the local variable `key`, e.g. it now
--    becomes `User:1`.
if not id then
  id = tostring(redis.call("INCR", model.id))
  key = namespace .. ":" .. id
end

-- In order to be more bullet-proof, we add this always, as opposed
-- to doing a SISMEMBER and then doing an SADD for the add case.
--
-- This is so we can cover custom IDs values for models.
redis.call("SADD", model.all, id)

-- Now comes the easy part: We first cleanup both indices and uniques.
-- It's important that we do this before saving, otherwise the old
-- values of the uniques and indices will be lost.
delete_uniques(key, id)
delete_indices(key, id)

-- Now that we've cleaned up, we can now persist the new attributes.
save(this, key)

-- In addition, we can now also save the new uniques and indices.
save_uniques(this, id)
save_indices(this, id)

-- Happy with a new record, we can now safely return. ^_^
return { 200, { "id", id }}
