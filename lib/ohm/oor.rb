require "redis"
require "nest"

module Oor
  VERSION = "0.0.1"

  def self.connect(options = {})
    @redis = Redis.new(options)
  end

  def self.redis
    @redis ||= Redis.new
  end

  def self.redis=(redis)
    @redis = redis
  end

  class Key
    attr :key

    def self.[](key)
      new(key)
    end

    def initialize(key, redis = ::Oor.redis)
      @key = ::Nest.new(key)
      @redis = redis
    end

    [:exists, :del, :scard, :sinterstore, :sdiffstore, :sort, :srem, :sismember, :sadd, :smembers].each do |meth|
      define_method(meth) do |*args|
        redis.send(meth, key, *args)
      end
    end

    alias to_s key
    alias inspect key

  protected

    def redis
      @redis
    end
  end
end
