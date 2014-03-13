-- This script receives four parameters, all encoded with
-- MessagePack. The decoded values are used for saving a model
-- instance in Redis, creating or updating a hash as needed and
-- updating zero or more sets (indices) and zero or more hashes
-- (unique indices).
--
-- # model
--
-- Table with one or two attributes:
--    name (model name)
--    id (model instance id, optional)
--
-- If the id is not provided, it is treated as a new record.
--
-- # attrs
--
-- Array with attribute/value pairs.
--
-- # indices
--
-- Fields and values to be indexed. Each key in the indices
-- table is mapped to an array of values. One index is created
-- for each field/value pair.
--
-- # uniques
--
-- Fields and values to be indexed as unique. Unlike indices,
-- values are not enumerable. If a field/value pair is not unique
-- (i.e., if there was already a hash entry for that field and
-- value), an error is returned with the UniqueIndexViolation
-- message and the field that triggered the error.
--
local model   = cmsgpack.unpack(ARGV[1])
local attrs   = cmsgpack.unpack(ARGV[2])
local indices = cmsgpack.unpack(ARGV[3])
local uniques = cmsgpack.unpack(ARGV[4])

local function save(model, attrs)
	if model.id == nil then
		model.id = redis.call("INCR", model.name .. ":id")
	end

	model.key = model.name .. ":" .. model.id

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

local function remove_uniques(model)
	local memo = model.key .. ":_uniques"

	for _, key in pairs(redis.call("HKEYS", memo)) do
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

save(model, attrs)

remove_indices(model)
index(model, indices)

remove_uniques(model, uniques)
unique(model, uniques)

return tostring(model.id)
