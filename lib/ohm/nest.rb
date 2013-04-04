module Ohm
  class Nest < String
    VERSION = "1.1.0"

    METHODS = [:append, :blpop, :brpop, :brpoplpush, :decr, :decrby,
    :del, :exists, :expire, :expireat, :get, :getbit, :getrange, :getset,
    :hdel, :hexists, :hget, :hgetall, :hincrby, :hkeys, :hlen, :hmget,
    :hmset, :hset, :hsetnx, :hvals, :incr, :incrby, :lindex, :linsert,
    :llen, :lpop, :lpush, :lpushx, :lrange, :lrem, :lset, :ltrim, :move,
    :persist, :publish, :rename, :renamenx, :rpop, :rpoplpush, :rpush,
    :rpushx, :sadd, :scard, :sdiff, :sdiffstore, :set, :setbit, :setex,
    :setnx, :setrange, :sinter, :sinterstore, :sismember, :smembers,
    :smove, :sort, :spop, :srandmember, :srem, :strlen, :subscribe,
    :sunion, :sunionstore, :ttl, :type, :unsubscribe, :watch, :zadd,
    :zcard, :zcount, :zincrby, :zinterstore, :zrange, :zrangebyscore,
    :zrank, :zrem, :zremrangebyrank, :zremrangebyscore, :zrevrange,
    :zrevrangebyscore, :zrevrank, :zscore, :zunionstore]

    attr :redis

    def initialize(key, redis)
      super(key.to_s)
      @redis = redis
    end

    def [](key)
      self.class.new("#{self}:#{key}", redis)
    end

    METHODS.each do |meth|
      define_method(meth) do |*args, &block|
        redis.call(meth, self, *args, &block)
      end
    end
  end
end
