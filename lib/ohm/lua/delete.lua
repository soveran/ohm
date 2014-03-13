-- This script receives three parameters, all encoded with
-- MessagePack. The decoded values are used for deleting a model
-- instance in Redis and removing any reference to it in sets
-- (indices) and hashes (unique indices).
--
-- # model
--
-- Table with three attributes:
--    id (model instance id)
--    key (hash where the attributes will be saved)
--    name (model name)
--
-- # uniques
--
-- Fields and values to be removed from the unique indices.
--
-- # tracked
--
-- Keys that share the lifecycle of this model instance, that
-- should be removed as this object is deleted.
--
local model   = cmsgpack.unpack(ARGV[1])
local uniques = cmsgpack.unpack(ARGV[2])
local tracked = cmsgpack.unpack(ARGV[3])

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
