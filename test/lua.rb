# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

begin
  Ohm.redis.script("flush")
rescue RuntimeError
  # We're running on Redis < 2.6, so we
  # skip all the test.
else
  setup do
    Ohm::Lua.new("./test/lua", Ohm.redis)
  end

  test do |lua|
    lua.redis.set("foo", "baz")

    res = lua.run_file("getset", keys: ["foo"], argv: ["bar"])
    assert_equal ["baz", "bar"], res
  end

  test do |lua|
    res = lua.run_file("ohm-save",
      keys: ["User"],
      argv: ["fname", "John", "lname", "Doe"])

    assert lua.redis.sismember("User:all", 1)
    assert_equal({ "fname" => "John", "lname" => "Doe" },
      lua.redis.hgetall("User:1"))
  end

  test do |lua|
    lua.redis.sadd("User:indices", "fname")
    lua.redis.sadd("User:indices", "lname")

    res = lua.run_file("save-with-indices",
      keys: ["User:1", "User:all", "User:indices"],
      argv: ["fname", "John", "lname", "Doe"])

    assert lua.redis.sismember("User:all", 1)

    assert lua.redis.sismember("User:fname:John", 1)
    assert lua.redis.sismember("User:lname:Doe", 1)
    assert lua.redis.sismember("User:1:_indices", "User:fname:John")
    assert lua.redis.sismember("User:1:_indices", "User:lname:Doe")
  end
end
