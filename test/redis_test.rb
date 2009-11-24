require File.join(File.dirname(__FILE__), "test_helper")

# This test suit is based on the Redis-rb spec,
# located at http://github.com/ezmobius/redis-rb/
class Foo
  attr_accessor :bar
  def initialize(bar)
    @bar = bar
  end

  def ==(other)
    @bar == other.bar
  end
end

class RedisTest < Test::Unit::TestCase
  setup do
    @legacy ||= begin
                  Ohm.redis.info["redis_version"] <= "1.02"
                end
  end

  describe "redis" do
    setup do
      @r ||= Ohm.redis
      @r.set("foo", "bar")
    end

    teardown do
      @r.flushdb
    end

    should "be able to GET a key" do
      assert_equal "bar", @r.get("foo")
    end

    should "be able to SET a key" do
      @r.set("foo", "nik")
      assert_equal "nik", @r.get("foo")
    end

    should "be able to SETNX(setnx)" do
      @r.set("foo", "nik")
      assert_equal "nik", @r.get("foo")
      @r.setnx("foo", "bar")
      assert_equal "nik", @r.get("foo")
    end

    should "be able to MSET keys" do
      unless @legacy
        @r.mset(:foo => "foobar", :bar => 1000)
        assert_equal ["foobar", "1000"], @r.mget("foo", "bar")
        assert_equal ["foobar", "1000", nil], @r.mget("foo", "bar", "baz")
      end
    end

    should "be able to MGET keys" do
      @r.set("foo", 1000)
      @r.set("bar", 2000)
      assert_equal ["1000", "2000"], @r.mget("foo", "bar")
      assert_equal ["1000", "2000", nil], @r.mget("foo", "bar", "baz")
    end

    should "be able to INCR(increment) a key" do
      @r.del("counter")
      assert_equal 1, @r.incr("counter")
      assert_equal 2, @r.incr("counter")
      assert_equal 3, @r.incr("counter")
    end

    should "be able to DECR(decrement) a key" do
      @r.del("counter")
      assert_equal 1, @r.incr("counter")
      assert_equal 2, @r.incr("counter")
      assert_equal 3, @r.incr("counter")
      assert_equal 2, @r.decr("counter")
      assert_equal 0, @r.decrby("counter", 2)
    end

    should "be able to RANDKEY(return a random key)" do
      assert_not_nil @r.randomkey
    end

    should "be able to RENAME a key" do
      @r.del "foo"
      @r.del "bar"
      @r.set("foo", "hi")
      @r.rename "foo", "bar"
      assert_equal "hi", @r.get("bar")
    end

    should "be able to RENAMENX(rename unless the new key already exists) a key" do
      @r.del "foo"
      @r.del "bar"
      @r.set("foo", "hi")
      @r.set("bar", "ohai")

      @r.renamenx "foo", "bar"

      assert_equal "ohai", @r.get("bar")
    end

    should "be able to EXISTS(check if key exists)" do
      @r.set("foo", "nik")
      assert @r.exists("foo")
      @r.del "foo"
      assert_equal false, @r.exists("foo")
    end

    should "be able to KEYS(glob for keys)" do
      @r.keys("f*").each do |key|
        @r.del key
      end
      @r.set("f", "nik")
      @r.set("fo", "nak")
      @r.set("foo", "qux")
      assert_equal ["f","fo", "foo"], @r.keys("f*").sort
    end

    should "be able to check the TYPE of a key" do
      @r.set("foo", "nik")
      assert_equal "string", @r.type("foo")
      @r.del "foo"
      assert_equal "none", @r.type("foo")
    end

    should "be able to push to the head of a list" do
      @r.lpush "list", "hello"
      @r.lpush "list", 42
      assert_equal "list", @r.type("list")
      assert_equal 2, @r.llen("list")
      assert_equal "42", @r.lpop("list")
      @r.del("list")
    end

    should "be able to push to the tail of a list" do
      @r.rpush "list", "hello"
      assert_equal "list", @r.type("list")
      assert_equal 1, @r.llen("list")
      @r.del("list")
    end

    should "be able to pop the tail of a list" do
      @r.rpush "list", "hello"
      @r.rpush "list", "goodbye"
      assert_equal "list", @r.type("list")
      assert_equal 2, @r.llen("list")
      assert_equal "goodbye", @r.rpop("list")
      @r.del("list")
    end

    should "be able to pop the head of a list" do
      @r.rpush "list", "hello"
      @r.rpush "list", "goodbye"
      assert_equal "list", @r.type("list")
      assert_equal 2, @r.llen("list")
      assert_equal "hello", @r.lpop("list")
      @r.del("list")
    end

    should "be able to get the length of a list" do
      @r.rpush "list", "hello"
      @r.rpush "list", "goodbye"
      assert_equal "list", @r.type("list")
      assert_equal 2, @r.llen("list")
      @r.del("list")
    end

    should "be able to get a range of values from a list" do
      @r.rpush "list", "hello"
      @r.rpush "list", "goodbye"
      @r.rpush "list", "1"
      @r.rpush "list", "2"
      @r.rpush "list", "3"
      assert_equal "list", @r.type("list")
      assert_equal 5, @r.llen("list")
      assert_equal ["1", "2", "3"], @r.lrange("list", 2, -1)
      @r.del("list")
    end

    should "be able to get all the values from a list" do
      @r.rpush "list", "1"
      @r.rpush "list", "2"
      @r.rpush "list", "3"
      assert_equal "list", @r.type("list")
      assert_equal 3, @r.llen("list")
      assert_equal ["1", "2", "3"], @r.list("list")
      @r.del("list")
    end

    should "be able to trim a list" do
      @r.rpush "list", "hello"
      @r.rpush "list", "goodbye"
      @r.rpush "list", "1"
      @r.rpush "list", "2"
      @r.rpush "list", "3"
      assert_equal "list", @r.type("list")
      assert_equal 5, @r.llen("list")
      @r.ltrim "list", 0, 1
      assert_equal 2, @r.llen("list")
      assert_equal ["hello", "goodbye"], @r.lrange("list", 0, -1)
      @r.del("list")
    end

    should "be able to get a value by indexing into a list" do
      @r.rpush "list", "hello"
      @r.rpush "list", "goodbye"
      assert_equal "list", @r.type("list")
      assert_equal 2, @r.llen("list")
      assert_equal "goodbye", @r.lindex("list", 1)
      @r.del("list")
    end

    should "be able to set a value by indexing into a list" do
      @r.rpush "list", "hello"
      @r.rpush "list", "hello"
      assert_equal "list", @r.type("list")
      assert_equal 2, @r.llen("list")
      assert @r.lset("list", 1, "goodbye")
      assert_equal "goodbye", @r.lindex("list", 1)
      @r.del("list")
    end

    should "be able to remove values from a list LREM" do
      @r.rpush "list", "hello"
      @r.rpush "list", "goodbye"
      assert_equal "list", @r.type("list")
      assert_equal 2, @r.llen("list")
      assert_equal 1, @r.lrem("list", 1, "hello")
      assert_equal ["goodbye"], @r.lrange("list", 0, -1)
      @r.del("list")
    end

    should "be able to pop values from a list and push them onto a temp list with RPOPLPUSH" do
      unless @legacy
        @r.rpush "list", 'one'
        @r.rpush "list", 'two'
        @r.rpush "list", 'three'
        assert_equal "list", @r.type('list')
        assert_equal 3, @r.llen('list')
        assert_equal %w(one two three), @r.lrange('list',0,-1)
        assert_equal [], @r.lrange('tmp',0,-1)
        assert_equal "three", @r.rpoplpush('list', 'tmp')
        assert_equal %w(three), @r.lrange('tmp',0,-1)
        assert_equal "two", @r.rpoplpush('list', 'tmp')
        assert_equal %w(two three), @r.lrange('tmp',0,-1)
        assert_equal "one", @r.rpoplpush('list', 'tmp')
        assert_equal %w(one two three), @r.lrange('tmp',0,-1)
      end
    end

    should "be able add members to a set" do
      @r.sadd "set", "key1"
      @r.sadd "set", "key2"
      assert_equal "set", @r.type("set")
      assert_equal 2, @r.scard("set")
      assert_equal ["key1", "key2"], @r.smembers("set").sort
      @r.del("set")
    end

    should "be able delete members to a set" do
      @r.sadd "set", "key1"
      @r.sadd "set", "key2"
      assert_equal "set", @r.type("set")
      assert_equal 2, @r.scard("set")
      assert_equal ["key1", "key2"], @r.smembers("set").sort
      @r.srem("set", "key1")
      assert_equal 1, @r.scard("set")
      assert_equal ["key2"], @r.smembers("set")
      @r.del("set")
    end

    should "be able count the members of a set" do
      @r.sadd "set", "key1"
      @r.sadd "set", "key2"
      assert_equal "set", @r.type("set")
      assert_equal 2, @r.scard("set")
      @r.del("set")
    end

    should "be able test for set membership" do
      @r.sadd "set", "key1"
      @r.sadd "set", "key2"
      assert_equal "set", @r.type("set")
      assert_equal 2, @r.scard("set")
      assert @r.sismember("set", "key1")
      assert @r.sismember("set", "key2")
      assert_equal false, @r.sismember("set", "notthere")
      @r.del("set")
    end

    should "be able to do set intersection" do
      @r.sadd "set", "key1"
      @r.sadd "set", "key2"
      @r.sadd "set2", "key2"
      assert_equal ["key2"], @r.sinter("set", "set2")
      @r.del("set")
    end

    should "be able to do set intersection and store the results in a key" do
      @r.sadd "set", "key1"
      @r.sadd "set", "key2"
      @r.sadd "set2", "key2"
      @r.sinterstore("newone", "set", "set2")
      assert_equal ["key2"], @r.smembers("newone")
      @r.del("set")
    end

    should "be able to do crazy SORT queries" do
      @r.set("dog_1", "louie")
      @r.rpush "dogs", 1
      @r.set("dog_2", "lucy")
      @r.rpush "dogs", 2
      @r.set("dog_3", "max")
      @r.rpush "dogs", 3
      @r.set("dog_4", "taj")
      @r.rpush "dogs", 4
      assert_equal ["louie"], @r.sort("dogs", :get => "dog_*", :limit => [0,1])
      assert_equal ["taj"], @r.sort("dogs", :get => "dog_*", :limit => [0,1], :order => "desc alpha")
    end

    should "be able add members to a zset ZADD" do
      unless @legacy
        @r.zadd 'zset', 1, 'set'
        assert_equal %w(set), @r.zrange('zset', 0, 1)
        assert_equal 1, @r.zcard('zset')
        @r.del('zset')
      end
    end

    should "be able count the members of a zset ZCARD" do
      unless @legacy
        @r.zadd 'zset', 1, 'foo'
        @r.zcard('zset')
        @r.del('zset')
      end
    end


    should "be able delete members of a zset ZREM" do
      unless @legacy
        @r.zadd 'zset', 1, 'set'
        assert_equal 1, @r.zcard('zset')
        @r.zadd 'zset', 2, 'set2'
        assert_equal 2, @r.zcard('zset')
        @r.zrem 'zset', 'set'
        assert_equal 1, @r.zcard('zset')
        @r.del('zset')
      end
    end

    should "be able to get a range of values from a zset ZRANGE" do
      unless @legacy
        @r.zadd 'zset', 1, 'set'
        @r.zadd 'zset', 2, 'set2'
        @r.zadd 'zset', 3, 'set3'
        assert_equal 3, @r.zcard('zset')
        assert_equal %w(set set2 set3), @r.zrange('zset', 0, 3)
        @r.del('set')
        @r.del('set2')
        @r.del('set3')
        @r.del('zset')
      end
    end

    should "be able to get a reverse range of values from a zset ZREVRANGE" do
      unless @legacy
        @r.zadd 'zset', 1, 'set'
        @r.zadd 'zset', 2, 'set2'
        @r.zadd 'zset', 3, 'set3'
        assert_equal 3, @r.zcard('zset')
        assert_equal %w(set3 set2 set), @r.zrevrange('zset', 0, 3)
        @r.del('zset')
      end
    end

    should "be able to get a range by score of values from a zset ZRANGEBYSCORE" do
      unless @legacy
        @r.zadd 'zset', 1, 'set'
        @r.zadd 'zset', 2, 'set2'
        @r.zadd 'zset', 3, 'set3'
        @r.zadd 'zset', 4, 'set4'
        assert_equal 4, @r.zcard('zset')
        assert_equal %w(set2 set3), @r.zrangebyscore('zset', 2, 3)
        @r.del('zset')
      end
    end

    should "provide info" do
      %w(last_save_time redis_version total_connections_received connected_clients total_commands_processed connected_slaves uptime_in_seconds used_memory uptime_in_days changes_since_last_save).each do |x|
        assert @r.info.keys.include?(x)
      end
    end

    should "be able to flush the database" do
      @r.set("key1", "keyone")
      @r.set("key2", "keytwo")
      assert_equal ["foo", "key1", "key2"], @r.keys("*").sort #foo from before
      @r.flushdb
      assert_equal [], @r.keys("*")
    end

    should "be able to provide the last save time" do
      savetime = @r.lastsave
      assert_equal Time, Time.at(savetime).class
      assert Time.at(savetime) <= Time.now
    end

    should "bgsave" do
      assert_nothing_raised do
        @r.bgsave
      end
    end
  end
end
