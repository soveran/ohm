require File.dirname(__FILE__) + "/test_helper"

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
  describe "redis" do
    setup do
      @r ||= $redis
      @r["foo"] = "bar"
    end

    teardown do
      @r.flush_db
    end

    should "should be able to GET a key" do
      assert_equal "bar", @r["foo"]
    end

    should "should be able to SET a key" do
      @r["foo"] = "nik"
      assert_equal "nik", @r["foo"]
    end

    should "should be able to SETNX(set_unless_exists)" do
      @r["foo"] = "nik"
      assert_equal "nik", @r["foo"]
      @r.set_unless_exists("foo", "bar")
      assert_equal "nik", @r["foo"]
    end

    should "should be able to INCR(increment) a key" do
      @r.delete("counter")
      assert_equal 1, @r.incr("counter")
      assert_equal 2, @r.incr("counter")
      assert_equal 3, @r.incr("counter")
    end

    should "should be able to DECR(decrement) a key" do
      @r.delete("counter")
      assert_equal 1, @r.incr("counter")
      assert_equal 2, @r.incr("counter")
      assert_equal 3, @r.incr("counter")
      assert_equal 2, @r.decr("counter")
      assert_equal 0, @r.decr("counter", 2)
    end

    should "should be able to RANDKEY(return a random key)" do
      assert_not_nil @r.randkey
    end

    should "should be able to RENAME a key" do
      @r.delete "foo"
      @r.delete "bar"
      @r["foo"] = "hi"
      @r.rename "foo", "bar"
      assert_equal "hi", @r["bar"]
    end

    should "should be able to RENAMENX(rename unless the new key already exists) a key" do
      @r.delete "foo"
      @r.delete "bar"
      @r["foo"] = "hi"
      @r["bar"] = "ohai"

      @r.rename_unless_exists "foo", "bar"

      assert_equal "ohai", @r["bar"]
    end

    should "should be able to EXISTS(check if key exists)" do
      @r["foo"] = "nik"
      assert @r.key?("foo")
      @r.delete "foo"
      assert_equal false, @r.key?("foo")
    end

    should "should be able to KEYS(glob for keys)" do
      @r.keys("f*").each do |key|
        @r.delete key
      end
      @r["f"] = "nik"
      @r["fo"] = "nak"
      @r["foo"] = "qux"
      assert_equal ["f","fo", "foo"], @r.keys("f*").sort
    end

    should "should be able to check the TYPE of a key" do
      @r["foo"] = "nik"
      assert_equal "string", @r.type?("foo")
      @r.delete "foo"
      assert_equal "none", @r.type?("foo")
    end

    should "should be able to push to the head of a list" do
      @r.push_head "list", "hello"
      @r.push_head "list", 42
      assert_equal "list", @r.type?("list")
      assert_equal 2, @r.list_length("list")
      assert_equal "42", @r.pop_head("list")
      @r.delete("list")
    end

    should "should be able to push to the tail of a list" do
      @r.push_tail "list", "hello"
      assert_equal "list", @r.type?("list")
      assert_equal 1, @r.list_length("list")
      @r.delete("list")
    end

    should "should be able to pop the tail of a list" do
      @r.push_tail "list", "hello"
      @r.push_tail "list", "goodbye"
      assert_equal "list", @r.type?("list")
      assert_equal 2, @r.list_length("list")
      assert_equal "goodbye", @r.pop_tail("list")
      @r.delete("list")
    end

    should "should be able to pop the head of a list" do
      @r.push_tail "list", "hello"
      @r.push_tail "list", "goodbye"
      assert_equal "list", @r.type?("list")
      assert_equal 2, @r.list_length("list")
      assert_equal "hello", @r.pop_head("list")
      @r.delete("list")
    end

    should "should be able to get the length of a list" do
      @r.push_tail "list", "hello"
      @r.push_tail "list", "goodbye"
      assert_equal "list", @r.type?("list")
      assert_equal 2, @r.list_length("list")
      @r.delete("list")
    end

    should "should be able to get a range of values from a list" do
      @r.push_tail "list", "hello"
      @r.push_tail "list", "goodbye"
      @r.push_tail "list", "1"
      @r.push_tail "list", "2"
      @r.push_tail "list", "3"
      assert_equal "list", @r.type?("list")
      assert_equal 5, @r.list_length("list")
      assert_equal ["1", "2", "3"], @r.list_range("list", 2, -1)
      @r.delete("list")
    end

    should "should be able to get all the values from a list" do
      @r.push_tail "list", "1"
      @r.push_tail "list", "2"
      @r.push_tail "list", "3"
      assert_equal "list", @r.type?("list")
      assert_equal 3, @r.list_length("list")
      assert_equal ["1", "2", "3"], @r.list("list")
      @r.delete("list")
    end

    should "should be able to trim a list" do
      @r.push_tail "list", "hello"
      @r.push_tail "list", "goodbye"
      @r.push_tail "list", "1"
      @r.push_tail "list", "2"
      @r.push_tail "list", "3"
      assert_equal "list", @r.type?("list")
      assert_equal 5, @r.list_length("list")
      @r.list_trim "list", 0, 1
      assert_equal 2, @r.list_length("list")
      assert_equal ["hello", "goodbye"], @r.list_range("list", 0, -1)
      @r.delete("list")
    end

    should "should be able to get a value by indexing into a list" do
      @r.push_tail "list", "hello"
      @r.push_tail "list", "goodbye"
      assert_equal "list", @r.type?("list")
      assert_equal 2, @r.list_length("list")
      assert_equal "goodbye", @r.list_index("list", 1)
      @r.delete("list")
    end

    should "should be able to set a value by indexing into a list" do
      @r.push_tail "list", "hello"
      @r.push_tail "list", "hello"
      assert_equal "list", @r.type?("list")
      assert_equal 2, @r.list_length("list")
      assert @r.list_set("list", 1, "goodbye")
      assert_equal "goodbye", @r.list_index("list", 1)
      @r.delete("list")
    end

    should "should be able to remove values from a list LREM" do
      @r.push_tail "list", "hello"
      @r.push_tail "list", "goodbye"
      assert_equal "list", @r.type?("list")
      assert_equal 2, @r.list_length("list")
      assert_equal 1, @r.list_rm("list", 1, "hello")
      assert_equal ["goodbye"], @r.list_range("list", 0, -1)
      @r.delete("list")
    end

    should "should be able add members to a set" do
      @r.set_add "set", "key1"
      @r.set_add "set", "key2"
      assert_equal "set", @r.type?("set")
      assert_equal 2, @r.set_count("set")
      assert_equal ["key1", "key2"], @r.set_members("set").sort
      @r.delete("set")
    end

    should "should be able delete members to a set" do
      @r.set_add "set", "key1"
      @r.set_add "set", "key2"
      assert_equal "set", @r.type?("set")
      assert_equal 2, @r.set_count("set")
      assert_equal ["key1", "key2"], @r.set_members("set").sort
      @r.set_delete("set", "key1")
      assert_equal 1, @r.set_count("set")
      assert_equal ["key2"], @r.set_members("set")
      @r.delete("set")
    end

    should "should be able count the members of a set" do
      @r.set_add "set", "key1"
      @r.set_add "set", "key2"
      assert_equal "set", @r.type?("set")
      assert_equal 2, @r.set_count("set")
      @r.delete("set")
    end

    should "should be able test for set membership" do
      @r.set_add "set", "key1"
      @r.set_add "set", "key2"
      assert_equal "set", @r.type?("set")
      assert_equal 2, @r.set_count("set")
      assert @r.set_member?("set", "key1")
      assert @r.set_member?("set", "key2")
      assert_equal false, @r.set_member?("set", "notthere")
      @r.delete("set")
    end

    should "should be able to do set intersection" do
      @r.set_add "set", "key1"
      @r.set_add "set", "key2"
      @r.set_add "set2", "key2"
      assert_equal ["key2"], @r.set_intersect("set", "set2")
      @r.delete("set")
    end

    should "should be able to do set intersection and store the results in a key" do
      @r.set_add "set", "key1"
      @r.set_add "set", "key2"
      @r.set_add "set2", "key2"
      @r.set_inter_store("newone", "set", "set2")
      assert_equal ["key2"], @r.set_members("newone")
      @r.delete("set")
    end

    should "should be able to do crazy SORT queries" do
      @r["dog_1"] = "louie"
      @r.push_tail "dogs", 1
      @r["dog_2"] = "lucy"
      @r.push_tail "dogs", 2
      @r["dog_3"] = "max"
      @r.push_tail "dogs", 3
      @r["dog_4"] = "taj"
      @r.push_tail "dogs", 4
      assert_equal ["louie"], @r.sort("dogs", :get => "dog_*", :limit => [0,1])
      assert_equal ["taj"], @r.sort("dogs", :get => "dog_*", :limit => [0,1], :order => "desc alpha")
    end

    should "should provide info" do
      [:last_save_time, :redis_version, :total_connections_received, :connected_clients, :total_commands_processed, :connected_slaves, :uptime_in_seconds, :used_memory, :uptime_in_days, :changes_since_last_save].each do |x|
        assert @r.info.keys.include?(x)
      end
    end

    should "should be able to flush the database" do
      @r["key1"] = "keyone"
      @r["key2"] = "keytwo"
      assert_equal ["foo", "key1", "key2"], @r.keys("*").sort #foo from before
      @r.flush_db
      assert_equal [], @r.keys("*")
    end

    should "should be able to provide the last save time" do
      savetime = @r.last_save
      assert_equal Time, Time.at(savetime).class
      assert Time.at(savetime) <= Time.now
    end

    should "should be able to MGET keys" do
      @r["foo"] = 1000
      @r["bar"] = 2000
      assert_equal ["1000", "2000"], @r.mget("foo", "bar")
      assert_equal ["1000", "2000", nil], @r.mget("foo", "bar", "baz")
    end

    should "should bgsave" do
      assert_nothing_raised do
        @r.bgsave
      end
    end
  end
end
