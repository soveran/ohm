# encoding: UTF-8

require "nest"
require "redis"
require "securerandom"
require "scrivener"
require "ohm/pureruby" unless defined?(Ohm::Model::Scripted)

module Ohm
  class Error < StandardError; end
  class MissingID < Error; end
  class UniqueIndexViolation < Error; end

  module Utils
    def self.const(context, name)
      case name
      when Symbol then context.const_get(name)
      else name
      end
    end

    def self.symbols(list)
      list.map(&:to_sym)
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

  module Collection
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

    def sort(options = {})
      if options.has_key?(:get)
        options[:get] = namespace["*->%s" % options[:get]]
        return execute { |key| key.sort(options) }
      end

      fetch(execute { |key| key.sort(options) })
    end

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

      dict.map { |k, v| key[:indices][k][v] }
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
      @indices ||= Utils.symbols(key[:indices].smembers)
    end

    def self.uniques
      @uniques ||= Utils.symbols(key[:uniques].smembers)
    end

    def self.collections
      @collections ||= Utils.symbols(key[:collections].smembers)
    end

    def self.index(attribute)
      @indices = nil
      key[:indices].sadd(attribute)
    end

    def self.unique(attribute)
      @uniques = nil
      key[:uniques].sadd(attribute)
    end

    def self.set(name, model)
      @collections = nil
      key[:collections].sadd(name)

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
