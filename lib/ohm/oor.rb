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

  class Key < BasicObject
    attr :key

    def self.[](key)
      new(key)
    end

    def initialize(key, redis = ::Oor.redis)
      @key = ::Nest.new(key)
      @redis = redis
    end

    def method_missing(meth, *args)
      redis.send(meth, key, *args)
    end

    def class
      Key
    end

    alias to_s key
    alias inspect key

  protected

    def redis
      @redis
    end
  end

  class String < Key
    def << (value)
      append(value)
    end

    def [] (start, stop = 0)
      substr(start, stop)
    end

    def class
      String
    end
  end

  class Set < Key
    def << (value)
      sadd(value)
    end

    def + (other)
      sunion(other)
    end

    def - (other)
      sdiff(other)
    end

    def & (other)
      sinter(other)
    end

    def each
      smembers.each do |member|
        yield member
      end
    end

    def include?(member)
      sismember(member)
    end

    def class
      Set
    end
  end

  class List < Key
    def << (value)
      rpush(value)
    end

    alias push <<

    def pop
      rpop
    end

    def shift
      lpop
    end

    def unshift(value)
      lpush(value)
    end

    def each
      lrange[0, -1].each do |member|
        yield member
      end
    end

    def class
      List
    end
  end
end
