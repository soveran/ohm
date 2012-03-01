require File.expand_path("./helper", File.dirname(__FILE__))

def redis
  Ohm.redis
end

setup do
  Ohm.redis.script("flush")

  redis.sadd("User:uniques", "email")
  redis.sadd("User:indices", "fname")
  redis.sadd("User:indices", "lname")
  redis.hset("User:uniques:email", "foo@bar.com", 1)

  Ohm::Lua.new("./test/lua", redis)
end

test "empty email doesn't choke" do |lua|
  res = lua.run_file("save",
    keys: ["User"],
    argv: ["email", nil])

  assert_equal [200, ["id", "1"]], res
  assert_equal "1", redis.hget("User:uniques:email", nil)
end

test "empty fname / lname doesn't choke" do |lua|
  res = lua.run_file("save",
    keys: ["User"],
    argv: ["email", nil, "fname", nil, "lname", nil])

  assert_equal [200, ["id", "1"]], res
  assert redis.sismember("User:indices:fname:", 1)
  assert redis.sismember("User:indices:lname:", 1)
end

test "returns the unique constraint error" do |lua|
  res = lua.run_file("save",
    keys: ["User"],
    argv: ["email", "foo@bar.com"])

  assert_equal [500, ["email", "not_unique"]], res
end

test "persists the unique entry properly" do |lua|
  lua.run_file("save",
    keys: ["User"],
    argv: ["email", "bar@baz.com"])

  assert_equal "1", redis.hget("User:uniques:email", "bar@baz.com")
end

test "adds the entry to User:all" do |lua|
  lua.run_file("save",
    keys: ["User"],
    argv: ["email", "bar@baz.com"])

  assert_equal 1, redis.scard("User:all")
end


test "saves the attributes" do |lua|
  lua.run_file("save",
    keys: ["User"],
    argv: ["email", "bar@baz.com", "fname", "John", "lname", "Doe"])

  assert_equal "bar@baz.com", redis.hget("User:1", "email")
  assert_equal "John", redis.hget("User:1", "fname")
  assert_equal "Doe", redis.hget("User:1", "lname")
end

test "indexes fname / lname" do |lua|
  lua.run_file("save",
    keys: ["User"],
    argv: ["email", "bar@baz.com", "fname", "John", "lname", "Doe"])

  assert redis.sismember("User:indices:fname:John", 1)
  assert redis.sismember("User:indices:lname:Doe", 1)
end

test "unique constraint during update" do |lua|
  lua.run_file("save",
    keys: ["User"],
    argv: ["email", "bar@baz.com", "fname", "John", "lname", "Doe"])

  res = lua.run_file("save",
    keys: ["User", "User:1"],
    argv: ["email", "bar@baz.com", "fname", "John", "lname", "Doe"])

  assert_equal [200, ["id", "1"]], res

  res = lua.run_file("save",
    keys: ["User", "User:1"],
    argv: ["email", "foo@bar.com", "fname", "Jane", "lname", "Doe"])

  assert_equal [200, ["id", "1"]], res
end

test "cleanup of existing indices during update" do |lua|
  lua.run_file("save",
    keys: ["User"],
    argv: ["email", "bar@baz.com", "fname", "John", "lname", "Doe"])

  res = lua.run_file("save",
    keys: ["User", "User:1"],
    argv: ["email", "foo@bar.com", "fname", "Jane", "lname", "Smith"])

  assert ! redis.sismember("User:indices:fname:John", 1)
  assert ! redis.sismember("User:indices:fname:Doe", 1)
end

test "cleanup of existing uniques during update" do |lua|
  lua.run_file("save",
    keys: ["User"],
    argv: ["email", "bar@baz.com", "fname", "John", "lname", "Doe"])

  res = lua.run_file("save",
    keys: ["User", "User:1"],
    argv: ["email", "foo@bar.com", "fname", "Jane", "lname", "Smith"])

  assert_equal nil, redis.hget("User:uniques:email", "bar@baz.com")
end

__END__
$VERBOSE = false

test "stress test for lua scripting" do |lua|
  require "benchmark"

  class User < Ohm::Model
    attribute :email
    attribute :fname
    attribute :lname

    index :email
    index :fname
    index :lname
  end

  t = Benchmark.measure do
    threads = 100.times.map do |i|
      Thread.new do
        User.create(email: "foo#{i}@bar.com",
                    fname: "Jane#{i}",
                    lname: "Smith#{i}")
      end
    end

    threads.each(&:join)
  end

  puts t
end

test "stress test for postgres + sequel (as a comparison)" do
  require "sequel"

  DB = Sequel.connect("postgres://cyx@localhost/postgres")
  DB[:users].truncate
  t = Benchmark.measure do
    threads = 100.times.map do |i|
      Thread.new do
        DB[:users].insert(email: "foo#{i}@bar.com",
                          fname: "John#{i}",
                          lname: "Doe#{i}")
      end
    end

    threads.each(&:join)
  end

  puts t
end

## Result for 100 threads:
#  0.040000   0.010000   0.050000 (  0.061512) - lua script
#  0.150000   0.180000   0.330000 (  0.259676) - postgres
#
## Result for 100 linear executions:
#
#  0.010000   0.010000   0.020000 (  0.032064) - lua script
#  0.010000   0.010000   0.020000 (  0.059540) - postgres
#
## It's also important to note that with 1K concurrent threads,
#  postgres throws a Sequel::PoolTimeout
