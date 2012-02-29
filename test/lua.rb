# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

setup do
  Ohm::Lua.new("./test/lua", Ohm.redis)
end

test do |lua|
  lua.redis.set("foo", "baz")

  res = lua.run("getset", keys: ["foo"], argv: ["bar"])
  assert_equal ["baz", "bar"], res
end

test do
  lua = Ohm::Lua.new(Ohm::ROOT + "/lua", Ohm.redis)

  res = lua.run("save",
    keys: ["User"],
    argv: ["fname", "John", "lname", "Doe"])

  assert lua.redis.sismember("User:all", 1)
  assert_equal({ "fname" => "John", "lname" => "Doe" },
    lua.redis.hgetall("User:1"))
end

test do |lua|
  lua.redis.sadd("User:indices", "fname")
  lua.redis.sadd("User:indices", "lname")

  res = lua.run("save-with-indices",
    keys: ["User:1", "User:all", "User:indices"],
    argv: ["fname", "John", "lname", "Doe"])

  assert lua.redis.sismember("User:all", 1)

  assert lua.redis.sismember("User:fname:John", 1)
  assert lua.redis.sismember("User:lname:Doe", 1)
  assert lua.redis.sismember("User:1:_indices", "User:fname:John")
  assert lua.redis.sismember("User:1:_indices", "User:lname:Doe")
end
