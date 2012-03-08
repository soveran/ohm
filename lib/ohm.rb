# encoding: UTF-8

require "nest"
require "redis"
require "securerandom"
require "scrivener"
require "ohm/transaction"

module Ohm
  # All of the known errors in Ohm can be traced back
  # to one of these exceptions classes.
  #
  # MissingID:
  #
  #   Comment.new.id # => error
  #   Comment.new.key # => error
  #
  #   Solution: You need to save your model first.
  #
  # IndexNotFound:
  #
  #   Comment.find(foo: "Bar") # => error
  #
  #   Solution: Comment.index :foo
  #
  # UniqueIndexViolation:
  #
  #   Raised when trying to save an object with a `unique` index.
  #
  #   Solution: rescue Ohm::UniqueIndexViolation during save,
  #             but also, do some validations even before attempting
  #             to save.
  class Error < StandardError; end
  class MissingID < Error; end
  class IndexNotFound < Error; end
  class UniqueIndexViolation < Error; end

  # Instead of monkey patching Kernel or trying to be clever, it's best
  # to confine all the helper methods in a Utils module.
  module Utils
    # Used by: `attribute`, `counter`, `set`, `reference`, `collection`
    #
    # Employed as a solution to avoid `NameError` problems when
    # trying to load models referring to other models not yet loaded.
    #
    # Example:
    #
    #   class Comment < Ohm::Model
    #     reference :user, User # NameError undefined constant User.
    #   end
    #
    #   Instead of relying on some clever `const_missing` hack, we can
    #   simply use a Symbol.
    #
    #   class Comment < Ohm::Model
    #     reference :user, :User
    #   end
    #
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

  # Stores the connection options for the Redis instance.
  #
  # Examples:
  #
  #   Ohm.connect(port: 6380, db: 1, host: "10.0.1.1")
  #   Ohm.connect(url: "redis://10.0.1.1:6380/1")
  #
  # All of the options are simply passed on to `Redis.connect`.
  #
  def self.connect(options = {})
    conn.start(options)
  end

  # Use this if you want to do quick adhoc redis commands against the
  # defined Ohm connection.
  #
  # Examples:
  #
  #   Ohm.redis.keys("User:*")
  #   Ohm.redis.set("foo", "bar")
  #
  def self.redis
    conn.redis
  end

  # A simple wrapper for Ohm.redis.flushdb.
  def self.flush
    redis.flushdb
  end

  # Defines all the base collection methods used by `Set` and `MultiSet`.
  # Starting in Ohm 1.0, all the collections are loaded in one pipeline.
  module Collection
    include Enumerable

    # Actually fetches the data from Redis in one go.
    def to_a
      fetch(ids)
    end

    def each
      to_a.each { |e| yield e }
    end

    def empty?
      size == 0
    end

    # Allows you to sort by any field in your model.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   User.all.sort_by(:name, order: "ALPHA")
    #   User.all.sort_by(:name, order: "ALPHA DESC")
    #   User.all.sort_by(:name, order: "ALPHA DESC", limit: [0, 10])
    #
    # Note: This is slower compared to just doing `sort`, specifically
    # because Redis has to read each individual Hash in order to sort them.
    #
    def sort_by(att, options = {})
      sort(options.merge(by: namespace["*->%s" % att]))
    end

    # Allows you to sort your models using their IDs. This is much faster
    # than `sort_by`. If you simply want to get records in ascending or
    # descending order, then this is the best method to do that.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   User.create(name: "John")
    #   User.create(name: "Jane")
    #
    #   User.all.sort.map(&:id) == ["1", "2"]
    #   # => true
    #
    #   User.all.sort(order: "ASC").map(&:id) == ["1", "2"]
    #   # => true
    #
    #   User.all.sort(order: "DESC").map(&:id) == ["2", "1"]
    #   # => true
    #
    def sort(options = {})
      if options.has_key?(:get)
        options[:get] = namespace["*->%s" % options[:get]]
        return execute { |key| key.sort(options) }
      end

      fetch(execute { |key| key.sort(options) })
    end

    # Check if a model is included in this SET.
    #
    # Example:
    #
    #   u = User.create
    #   User.all.include?(u)
    #   # => true
    #
    # Note: Ohm simply checks that the model's ID is included in the set.
    #       It doesn't do any form of type checking.
    #
    def include?(model)
      execute { |key| key.sismember(model.id) }
    end

    # The total members of this SET (SCARD).
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

  class Set < Struct.new(:key, :namespace, :model)
    include Collection

    def add(model)
      key.sadd(model.id)
    end

    def find(dict)
      keys = model.filters(dict)
      keys.push(key)

      MultiSet.new(keys, namespace, model)
    end

    def replace(models)
      ids = models.map { |model| model.id }

      key.redis.multi do
        key.del
        ids.each { |id| key.sadd(id) }
      end
    end

  private
    def execute
      yield key
    end
  end

  class MultiSet < Struct.new(:keys, :namespace, :model)
    include Collection

    def find(dict)
      keys = model.filters(dict)
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

  class Model
    include Scrivener::Validations

    def self.conn
      @conn ||= Connection.new(name, Ohm.conn.options)
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
      @lua ||= Lua.new(File.join(Dir.pwd, "lua"), db)
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

    def self.filters(dict)
      unless dict.kind_of?(Hash)
        raise ArgumentError,
          "You need to supply a hash with filters. " +
          "If you want to find by ID, use #{self}[id] instead."
      end

      dict.map { |k, v| toindices(k, v) }.flatten
    end

    def self.toindices(att, val)
      raise IndexNotFound unless indices.include?(att)

      if val.kind_of?(Enumerable)
        val.map { |v| key[:indices][att][v] }
      else
        [key[:indices][att][val]]
      end
    end

    def self.find(dict)
      keys = filters(dict)

      if keys.size == 1
        Ohm::Set.new(keys.first, key, self)
      else
        Ohm::MultiSet.new(keys, key, self)
      end
    end

    def self.indices
      @indices ||= []
    end

    def self.uniques
      @uniques ||= []
    end

    def self.collections
      @collections ||= []
    end

    def self.index(attribute)
      indices << attribute unless indices.include?(attribute)
    end

    def self.unique(attribute)
      uniques << attribute unless uniques.include?(attribute)
    end

    def self.set(name, model)
      collections << name unless collections.include?(name)

      define_method name do
        model = Utils.const(self.class, model)

        Ohm::Set.new(key[name], model.key, model)
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

    def get(att)
      @attributes[att] = key.hget(att)
    end

    def set(att, val)
      val.to_s.empty? ? key.hdel(att) : key.hset(att, val)
      @attributes[att] = val
    end

    def new?
      !defined?(@id)
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
      attrs[:errors] = errors if errors.any?

      return attrs
    end

    def to_json(*args)
      to_hash.to_json(*args)
    end

    def save(&block)
      return if not valid?
      save!(&block)
    end

    def save!
      transaction do |t|
        t.watch(*_unique_keys)
        t.watch(key) if not new?

        t.before do
          _initialize_id if new?
        end

        t.read do |store|
          _verify_uniques
          store.existing = key.hgetall
          store.uniques  = _read_index_type(:uniques)
          store.indices  = _read_index_type(:indices)
        end

        t.write do |store|
          model.key[:all].sadd(id)
          _delete_uniques(store.existing)
          _delete_indices(store.existing)
          _save
          _save_indices(store.indices)
          _save_uniques(store.uniques)
        end

        yield t if block_given?
      end

      return self
    end

    def delete
      transaction do |t|
        t.read do |store|
          store.existing = key.hgetall
        end

        t.write do |store|
          _delete_uniques(store.existing)
          _delete_indices(store.existing)
          model.collections.each { |e| key[e].del }
          model.key[:all].srem(id)
          key[:counters].del
          key.del
        end

        yield t if block_given?
      end
    end

    def update(attributes)
      update_attributes(attributes)
      save
    end

    def update_attributes(atts)
      atts.each { |att, val| send(:"#{att}=", val) }
    end

    def transaction
      txn = Transaction.new { |t| yield t }
      txn.commit(db)
    end

  protected
    attr_writer :id

    def _initialize_id
      @id = model.new_id.to_s
    end

    def _skip_empty(atts)
      {}.tap do |ret|
        atts.each do |att, val|
          ret[att] = send(att).to_s unless val.to_s.empty?
        end
      end
    end

    def _unique_keys
      model.uniques.map { |att| model.key[:uniques][att] }
    end

    def _save
      key.del
      key.hmset(*_skip_empty(attributes).flatten)
    end

    def _verify_uniques
      if att = _detect_duplicate
        raise UniqueIndexViolation, "#{att} is not unique."
      end
    end

    def _detect_duplicate
      model.uniques.detect do |att|
        id = model.key[:uniques][att].hget(send(att))
        id && id != self.id.to_s
      end
    end

    def _read_index_type(type)
      {}.tap do |ret|
        model.send(type).each do |att|
          ret[att] = send(att)
        end
      end
    end

    def _save_uniques(uniques)
      uniques.each do |att, val|
        model.key[:uniques][att].hset(val, id)
      end
    end

    def _delete_uniques(atts)
      model.uniques.each do |att|
        model.key[:uniques][att].hdel(atts[att.to_s])
      end
    end

    def _delete_indices(atts)
      model.indices.each do |att|
        val = atts[att.to_s]

        if val
          model.key[:indices][att][val].srem(id)
        end
      end
    end

    def _save_indices(indices)
      indices.each do |att, val|
        model.toindices(att, val).each do |index|
          index.sadd(id)
        end
      end
    end
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

      begin
        redis.evalsha(sha(script), keys.size, *keys, *argv)
      rescue RuntimeError
        redis.eval(script, keys.size, *keys, *argv)
      end
    end

  private
    def read(file)
      File.read("%s/%s.lua" % [dir, file])
    end

    def sha(script)
      Digest::SHA1.hexdigest(script)
    end
  end
end
