# encoding: UTF-8

require "base64"
require "redis"
require "nest"

module Ohm
  class Error < StandardError; end
  class MissingID < Error; end

  module ConnectionHandling
    def connect(options = {})
      self.redis = nil
      @options = options
    end

    def redis
      threaded[self] ||= Redis.connect(options)
    end

    def redis=(redis)
      threaded[self] = redis
    end

    def threaded
      Thread.current[:Ohm] ||= {}
    end

    def options
      @options || {}
    end
  end
  extend ConnectionHandling

  class Model
    extend ConnectionHandling

    def self.db
      options.any? ? redis : Ohm.redis
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

    def self.attributes
      @attributes ||= []
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

      attributes << name unless attributes.include?(name)
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
        @elements ||= begin
          ids = members

          arr = model.db.pipelined do
            ids.each { |id| key[id].hgetall }
          end

          arr.map.with_index do |atts, idx|
            model.new(Hash[*atts].update(id: ids[idx]))
          end
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
      !@id
    end

    def save
      if new?
        _initialize_id
        key.hmset(*_flattened_attributes)

        model.key[:all].sadd(id)
      else
        key.del
        key.hmset(*_flattened_attributes)
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
