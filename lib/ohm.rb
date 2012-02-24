# encoding: UTF-8

require "base64"
require "redis"
require "nest"

module Ohm
  class Error < StandardError; end
  class MissingID < Error; end

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

    class Collection < Struct.new(:set, :key, :model)
      include Enumerable

      def each
        to_a.each do |e|
          yield e
        end
      end

      def size
        set.scard
      end

      def sort(options = {})
        @sort = options
        return self
      end

      def sort_by(att, options = {})
        sort(options.merge(by: key["*->%s" % att]))
      end

      def to_a
        ids = members

        arr = model.db.pipelined do
          ids.each { |id| key[id].hgetall }
        end

        arr.map.with_index do |atts, idx|
          model.new(Hash[*atts].update(id: ids[idx]))
        end
      end

      def members
        if defined?(@sort)
          set.sort(@sort)
        else
          set.smembers
        end
      end
    end

    def self.all
      Collection.new(key[:all], key, self)
    end

    def self.create(atts)
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

    attr_accessor :id

    def initialize(atts = {})
      @_attributes = {}
      update_attributes(atts)
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

    def save
      if new?
        _initialize_id

        db.multi do
          key.hmset(*_flattened_attributes)
          model.key[:all].sadd(id)
        end
      else
        db.multi do
          key.del
          key.hmset(*_flattened_attributes)
        end
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
end
