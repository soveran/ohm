module Ohm

  # Represents a key in Redis.
  class Key < String
    attr :redis

    def initialize(name, redis = nil)
      @redis = redis
      super(name.to_s)
    end

    Volatile = new("~")

    def self.[](*args)
      new(args.join(":"))
    end

    def [](key)
      self.class[self, key]
    end

    def volatile
      self.index(Volatile) == 0 ? self : Volatile[self]
    end

    def +(other)
      self.class.new("#{self}+#{other}")
    end

    def -(other)
      self.class.new("#{self}-#{other}")
    end

    [:append, :blpop, :brpop, :decr, :decrby, :del, :exists, :expire,
    :expireat, :get, :getset, :hdel, :hexists, :hget, :hgetall,
    :hincrby, :hkeys, :hlen, :hmset, :hset, :hvals, :incr, :incrby,
    :lindex, :llen, :lpop, :lpush, :lrange, :lrem, :lset, :ltrim, :move,
    :rename, :renamenx, :rpop, :rpoplpush, :rpush, :sadd, :scard,
    :sdiff, :sdiffstore, :set, :setex, :setnx, :sinter, :sinterstore,
    :sismember, :smembers, :smove, :sort, :spop, :srandmember, :srem,
    :substr, :sunion, :sunionstore, :ttl, :type, :zadd, :zcard,
    :zincrby, :zinterstore, :zrange, :zrangebyscore, :zrank, :zrem,
    :zremrangebyrank, :zremrangebyscore, :zrevrange, :zrevrank, :zscore,
    :zunionstore].each do |meth|
      define_method(meth) do |*args|
        redis.send(meth, self, *args)
      end
    end
  end
end
