# encoding: UTF-8

require "digest/sha1"
require "nest"
require "redis"
require "securerandom"

module Ohm
  class Error < StandardError; end
  class MissingID < Error; end
  class IndexNotFound < Error; end
  class UniqueIndexViolation < Error; end

  ROOT = File.expand_path("../", File.dirname(__FILE__))

  module Utils
    def self.const(context, name)
      case name
      when Symbol then context.const_get(name)
      else name
      end
    end
  end

  class Connection
    attr_accessor :context
    attr_accessor :options

    def initialize(context = :main, options = {})
      @context = context
      @options = options
    end

    def reset!
      threaded[context] = nil
    end

    def start(options = {})
      self.options = options
      self.reset!
    end

    def redis
      threaded[context] ||= Redis.connect(options)
    end

    def threaded
      Thread.current[:ohm] ||= {}
    end
  end

  def self.conn
    @conn ||= Connection.new
  end

  def self.connect(options = {})
    conn.start(options)
  end

  def self.redis
    conn.redis
  end

  def self.flush
    redis.flushdb
  end

  module CollectionConcerns
    include Enumerable

    def all
      fetch(ids)
    end
    alias :to_a :all

    def each
      all.each { |e| yield e }
    end

    def empty?
      size == 0
    end

    def sort_by(att, options = {})
      sort(options.merge(by: namespace["*->%s" % att]))
    end

  private
    def fetch(ids)
      arr = model.db.pipelined do
        ids.each { |id| namespace[id].hgetall }
      end

      return [] if arr.nil?

      arr.map.with_index do |atts, idx|
        model.new(Hash[*atts].update(id: ids[idx]))
      end
    end
  end

  class Collection < Struct.new(:key, :namespace, :model)
    include CollectionConcerns

    def sort(options = {})
      if options.has_key?(:get)
        options[:get] = namespace["*->%s" % options[:get]]
        return key.sort(options)
      end

      fetch(key.sort(options))
    end
  end

  class List < Collection
    def ids
      key.lrange(0, -1)
    end

    def size
      key.llen
    end

    def first
      model[key.lindex(0)]
    end

    def last
      model[key.lindex(-1)]
    end

    def include?(model)
      ids.include?(model.id.to_s)
    end

    def replace(models)
      ids = models.map { |model| model.id }

      model.db.multi do
        key.del
        ids.each { |id| key.rpush(id) }
      end
    end
  end

  class MultiSet < Struct.new(:keys, :namespace, :model)
    include CollectionConcerns

    def include?(model)
      execute { |key| key.sismember(model.id) }
    end

    def size
      execute { |key| key.scard }
    end

    def first(options = {})
      opts = options.dup
      opts.merge!(limit: [0, 1])

      if opts[:by]
        sort_by(opts.delete(:by), opts).first
      else
        sort(opts).first
      end
    end

    def ids
      execute { |key| key.smembers }
    end

    def [](id)
      model[id] if execute { |key| key.sismember(id) }
    end

    def sort(options = {})
      if options.has_key?(:get)
        options[:get] = namespace["*->%s" % options[:get]]
        return execute { |key| key.sort(options) }
      end

      fetch(execute { |key| key.sort(options) })
    end

    def find(conditions)
      keys = conditions.map { |k, v| namespace[:indices][k][v] }
      keys.push(*self.keys)

      MultiSet.new(keys, namespace, model)
    end

  private
    def execute
      key = namespace[:temp][SecureRandom.uuid]
      key.sinterstore(*keys)

      begin
        yield key
      ensure
        key.del
      end
    end
  end

  class Set < Collection
    def first(options = {})
      opts = options.dup
      opts.merge!(limit: [0, 1])

      if opts[:by]
        sort_by(opts.delete(:by), opts).first
      else
        sort(opts).first
      end
    end

    def ids
      key.smembers
    end

    def include?(record)
      key.sismember(record.id)
    end

    def size
      key.scard
    end

    def [](id)
      model[id] if key.sismember(id)
    end

    def replace(models)
      ids = models.map { |model| model.id }

      key.redis.multi do
        key.del
        ids.each { |id| key.sadd(id) }
      end
    end

    def find(conditions)
      keys = conditions.map { |k, v| namespace[:indices][k][v] }
      keys.push(key)

      MultiSet.new(keys, namespace, model)
    end
  end

  class Model
    def self.conn
      @conn ||= Connection.new(name)
    end

    def self.connect(options)
      @key = nil
      @lua = nil
      conn.start(options)
    end

    def self.db
      conn.redis
    end

    def self.lua
      @lua ||= Lua.new(File.join(Ohm::ROOT, "lua"), db)
    end

    def self.key
      @key ||= Nest.new(self.name, db)
    end

    def self.[](id)
      new(id: id).load! if id && exists?(id)
    end

    def self.to_proc
      lambda { |id| self[id] }
    end

    def self.exists?(id)
      key[:all].sismember(id)
    end

    def self.new_id
      key[:id].incr
    end

    def self.with(att, val)
      id = key[:uniques][att].hget(val)
      id && self[id]
    end

    def self.find(hash)
      unless hash.kind_of?(Hash)
        raise ArgumentError,
          "You need to supply a hash with filters. " +
          "If you want to find by ID, use #{self}[id] instead."
      end

      keys = hash.map { |k, v| key[:indices][k][v] }

      if keys.size == 1
        Ohm::Set.new(keys.first, key, self)
      else
        Ohm::MultiSet.new(keys, key, self)
      end
    end

    def self.index(attribute)
      key[:indices].sadd(attribute)
    end

    def self.unique(attribute)
      key[:uniques].sadd(attribute)
    end

    def self.list(name, model)
      key[:lists].sadd(name)

      define_method name do
        Ohm::List.new(key[name], model.key, Utils.const(self.class, model))
      end
    end

    def self.set(name, model)
      key[:sets].sadd(name)

      define_method name do
        Ohm::Set.new(key[name], model.key, Utils.const(self.class, model))
      end
    end

    def self.to_reference
      name.to_s.
        match(/^(?:.*::)*(.*)$/)[1].
        gsub(/([a-z\d])([A-Z])/, '\1_\2').
        downcase.to_sym
    end

    def self.collection(name, model, reference = to_reference)
      define_method name do
        model = Utils.const(self.class, model)
        model.find(:"#{reference}_id" => id)
      end
    end

    def self.reference(name, model)
      reader = :"#{name}_id"
      writer = :"#{name}_id="

      index reader

      define_method(reader) do
        @attributes[reader]
      end

      define_method(writer) do |value|
        @_memo.delete(name)
        @attributes[reader] = value
      end

      define_method(:"#{name}=") do |value|
        @_memo.delete(name)
        send(writer, value ? value.id : nil)
      end

      define_method(name) do
        @_memo[name] ||= begin
          model = Utils.const(self.class, model)
          model[send(reader)]
        end
      end
    end

    def self.attribute(name, cast = nil)
      if cast
        define_method(name) do
          cast[@attributes[name]]
        end
      else
        define_method(name) do
          @attributes[name]
        end
      end

      define_method(:"#{name}=") do |value|
        @attributes[name] = value
      end
    end

    def self.counter(name)
      define_method(name) do
        return 0 if new?

        key[:counters].hget(name).to_i
      end

      key[:counters].sadd(name)
    end

    def self.all
      Set.new(key[:all], key, self)
    end

    def self.create(atts = {})
      new(atts).save
    end

    def model
      self.class
    end

    def db
      model.db
    end

    def key
      model.key[id]
    end

    def initialize(atts = {})
      @attributes = {}
      @_memo = {}
      update_attributes(atts)
    end

    def id
      raise MissingID if not defined?(@id)
      @id
    end

    def ==(other)
      other.kind_of?(model) && other.key == key
    rescue MissingID
      false
    end

    def load!
      update_attributes(key.hgetall) unless new?
      return self
    end

    def new?
      !defined?(@id)
    end

    def save
      response = model.lua.run(Ohm::SAVE,
        keys: [model, (key unless new?)],
        argv: @attributes.flatten)

      case response[0]
      when 200
        @id = response[1][1]
      when 500
        raise UniqueIndexViolation, "#{response[1][0]} is not unique"
      end

      return self
    end

    def incr(att, count = 1)
      key[:counters].hincrby(att, count)
    end

    def decr(att, count = 1)
      incr(att, -count)
    end

    def hash
      new? ? super : key.hash
    end
    alias :eql? :==

    def attributes
      @attributes
    end

    def to_hash
      attrs = {}
      attrs[:id] = id unless new?

      return attrs
    end

    def to_json
      to_hash.to_json
    end

    def update(attributes)
      update_attributes(attributes)
      save
    end

    def update_attributes(atts)
      atts.each { |att, val| send(:"#{att}=", val) }
    end

    def delete
      model.lua.run(Ohm::DELETE, keys: [model, key])
    end

  protected
    attr_writer :id
  end

  class Lua
    attr :dir
    attr :redis
    attr :files
    attr :scripts

    def initialize(dir, redis)
      @dir = dir
      @redis = redis
      @files = Hash.new { |h, cmd| h[cmd] = read(cmd) }
      @scripts = {}
    end

    def run_file(file, options)
      run(files[file], options)
    end

    def run(script, options)
      keys = options[:keys]
      argv = options[:argv]

      minified = minify(script)

      begin
        redis.evalsha(sha(minified), keys.size, *keys, *argv)
      rescue RuntimeError
        redis.eval(minified, keys.size, *keys, *argv)
      end
    end

  private
    def read(file)
      File.read("%s/%s.lua" % [dir, file])
    end

    def minify(code)
      code.
        gsub(/^\s*--.*$/, ""). # Remove comments
        gsub(/^\s+$/, "").     # Remove empty lines
        gsub(/^\s+/, "")       # Remove leading spaces
    end

    def sha(script)
      Digest::SHA1.hexdigest(script)
    end
  end

  SAVE = (<<-EOT).gsub(/^ {4}/, "")
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
  EOT

  DELETE = (<<-EOT).gsub(/^ {4}/, "")
    -- COMMAND delete
    -- KEYS[1] the namespace, e.g. `User`
    -- KEYS[2] the actual Hash key e.g. `User:1`
    --         for the case of a new record, we leave this blank.

    local namespace  = KEYS[1]
    local key        = KEYS[2]
    local id         = string.match(key, "(%w+)$")

    local model = {
      id      = namespace .. ":id",
      all     = namespace .. ":all",
      uniques = namespace .. ":uniques",
      indices = namespace .. ":indices",
      sets    = namespace .. ":sets",
      lists   = namespace .. ":lists",
      key     = namespace .. ":%s"
    }

    local meta = {
      uniques = redis.call("SMEMBERS", model.uniques),
      indices = redis.call("SMEMBERS", model.indices),
      sets    = redis.call("SMEMBERS", model.sets),
      lists   = redis.call("SMEMBERS", model.lists)
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

    delete_collection(key, meta.sets)
    delete_collection(key, meta.lists)

    -- Permanently deleted, now we can safely return.
    return { 200, { "id", id }}
  EOT
end
