# encoding: UTF-8

require "base64"
require "digest/sha1"
require "redis"
require "nest"

require File.expand_path("ohm/transaction", File.dirname(__FILE__))

module Ohm
  class Error < StandardError; end
  class MissingID < Error; end
  class IndexNotFound < Error; end

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


  class Model
    def self.conn
      @conn ||= Connection.new(name)
    end

    def self.connect(options)
      conn.start(options)
    end

    def self.db
      conn.redis
    end

    def self.key
      @key ||= Nest.new(self.name, db)
    end

    def self.[](id)
      new(id: id).load! if id && exists?(id)
    end

    def self.exists?(id)
      key[:all].sismember(id)
    end

    def self.new_id
      key[:id].incr
    end

    def self.attribute(name, cast = nil)
      if cast
        define_method(name) do
          cast[@_attributes[name]]
        end
      else
        define_method(name) do
          @_attributes[name]
        end
      end

      define_method(:"#{name}=") do |value|
        @_attributes[name] = value
      end
    end

    class Collection < Struct.new(:key, :namespace, :model)
      include Enumerable

      def each
        fetch(key.smembers).each do |e|
          yield e
        end
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

      def include?(record)
        key.sismember(record.id)
      end

      def size
        key.scard
      end

      def sort(options = {})
        fetch(key.sort(options))
      end

      def sort_by(att, options = {})
        sort(options.merge(by: namespace["*->%s" % att]))
      end

      def fetch(ids)
        arr = model.db.pipelined do
          ids.each { |id| key[id].hgetall }
        end

        arr.map.with_index do |atts, idx|
          model.new(Hash[*atts].update(id: ids[idx]))
        end
      end
    end

    def self.all
      Collection.new(key[:all], key, self)
    end

    def self.create(atts)
      new(atts).save
    end

    def self.encode(val)
      Base64.encode64(String(val)).gsub("\n", "")
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

    attr_writer :id

    def initialize(atts = {})
      @_attributes = {}
      update_attributes(atts)
    end

    def id
      @id or raise MissingID
    end

    def ==(other)
      other.kind_of?(model) && other.key == key
    rescue MissingID
      false
    end

    def update_attributes(atts)
      atts.each { |att, val| send(:"#{att}=", val) }
    end

    def load!
      update_attributes(key.hgetall) unless new?

      return self
    end

    def new?
      !defined?(@id)
    end

    def transaction(&block)
      txn = Transaction.define(&block)
      txn.commit(db)
    end

    def save(&block)
      return create(&block) if new?

      transaction do |t|
        t.write do
          key.del
          key.hmset(*_flattened_attributes)
        end

        yield t if block_given?
      end

      return self
    end

    def create(&block)
      transaction do |t|
        t.before do
          _initialize_id
        end

        t.write do
          key.hmset(*_flattened_attributes)
          model.key[:all].sadd(id)
        end

        yield t if block_given?
      end

      return self
    end

    def _initialize_id
      @id ||= model.new_id
    end

    def _flattened_attributes
      @_attributes.flatten
    end
  end

  module Index
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def index_key_for(att, val)
        raise IndexNotFound, att unless indices.include?(att)

        key[att][encode(val)]
      end

      def find(hash)
        unless hash.kind_of?(Hash)
          raise ArgumentError,
            "You need to supply a hash with filters. " +
            "If you want to find by ID, use #{self}[id] instead."
        end

        keys = hash.map { |k, v| index_key_for(k, v) }

        # FIXME: this should do the old way of SINTERing stuff.
        Ohm::Model::Collection.new(keys.first, key, self)
      end

      def indices
        @indices ||= []
      end

      def index(attribute)
        indices << attribute unless indices.include?(attribute)
      end
    end

    def _index_key_for(att, val)
      model.index_key_for(att, val)
    end

    def _indices_key
      @_indices_key ||= key[:_indices]
    end

    def _indices
      {}.tap do |ret|
        model.indices.each do |att|
          ret[att] = send(att)
        end
      end
    end

    def _add_to_index(att, val)
      index = _index_key_for(att, val)
      index.sadd(id)
      _indices_key.sadd(index)
    end

    def _collection?(value)
      value.kind_of?(Enumerable) && value.kind_of?(String) == false
    end

    def _save_indices(hash)
      hash.each do |att, val|
        if _collection?(val)
          val.each { |v| _add_to_index(att, v) }
        else
          _add_to_index(att, val)
        end
      end
    end

    def save
      super do |t|
        yield t if block_given?

        t.watch(_indices_key) unless new?

        t.read do |store|
          store.old_indices = _indices_key.smembers
          store.new_indices = _indices
        end

        t.write do |store|
          store.old_indices.each { |index| db.srem(index, id) }
          _indices_key.del
          _save_indices(store.new_indices)
        end
      end
    end
  end

  class Lua
    attr :dir
    attr :redis
    attr :cache

    def initialize(dir, redis)
      @dir = dir
      @redis = redis
      @cache = Hash.new { |h, cmd| h[cmd] = read(cmd) }
    end

    def run(command, options)
      keys = options[:keys]
      argv = options[:argv]

      begin
        redis.evalsha(sha(command), keys.size, *keys, *argv)
      rescue RuntimeError
        redis.eval(cache[command], keys.size, *keys, *argv)
      end
    end

  private
    def read(name)
      minify(File.read("%s/%s.lua" % [dir, name]))
    end

    def minify(code)
      code.
        gsub(/^\s*--.*$/, ""). # Remove comments
        gsub(/^\s+$/, "").     # Remove empty lines
        gsub(/^\s+/, "")       # Remove leading spaces
    end

    def sha(command)
      Digest::SHA1.hexdigest(cache[command])
    end
  end
end
