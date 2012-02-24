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

test do |lua|
  res = lua.run("save",
    keys: ["User:1", "User:all"],
    argv: ["fname", "John", "lname", "Doe"])

  assert lua.redis.sismember("User:all", 1)
  assert_equal({ "fname" => "John", "lname" => "Doe" },
    lua.redis.hgetall("User:1"))
end
