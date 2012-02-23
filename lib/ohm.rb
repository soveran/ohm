# encoding: UTF-8

require "base64"
require "redis"
require "nest"

module Ohm
  def self.redis
    @redis ||= Redis.connect(options)
  end

  def self.redis=(redis)
    @redis = redis
  end

  def self.connect(options = {})
    @redis = nil
    @options = options
  end

  def self.options
    @options ||= {}
  end

  class Error < StandardError; end
  class MissingID < Error; end

  class Model
    def self.db
      @db ||= (defined?(@options) ? Redis.connect(options) : Ohm.redis)
    end

    def self.connect(options = {})
      @db = nil
      @options = options
    end

    def self.options
      @options
    end

    def self.key
      @key ||= Nest.new(key, db)
    end

    def self.exists?(id)
      key[:all].sismember(id)
    end

    def self.new_id
      key[:id].incr.to_s
    end

    def model
      self.class
    end

    def db
      model.db
    end

    def _initialize_id
      @id ||= model.new_id
    end
  end
end
