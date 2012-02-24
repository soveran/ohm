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
