require_relative "helper"

scope do
  setup do
    redis = Redic.new
    redis.call("FLUSHDB")

    nido = Nido.new("User:tmp")

    [1, 2, 3].each { |i| redis.call("SADD", "A", i) }
    [1, 4, 5].each { |i| redis.call("SADD", "B", i) }

    [10, 11, 12].each { |i| redis.call("SADD", "C", i) }
    [11, 12, 13].each { |i| redis.call("SADD", "D", i) }
    [12, 13, 14].each { |i| redis.call("SADD", "E", i) }

    [10, 11, 12].each { |i| redis.call("SADD", "F", i) }
    [11, 12, 13].each { |i| redis.call("SADD", "G", i) }
    [12, 13, 14].each { |i| redis.call("SADD", "H", i) }

    [redis, nido]
  end

  test "special condition: single argument returns that arg" do
    assert_equal "A", Ohm::Command[:sinterstore, "A"]
  end

  test "full stack test"  do |redis, nido|
    cmd1 = Ohm::Command[:sinterstore, "A", "B"]

    res = cmd1.call(nido, redis)
    assert_equal ["1"], redis.call("SMEMBERS", res)

    cmd1.clean
    assert_equal 0, redis.call("EXISTS", res)

    cmd2 = Ohm::Command[:sinterstore, "C", "D", "E"]
    cmd3 = Ohm::Command[:sunionstore, cmd1, cmd2]

    res = cmd3.call(nido, redis)
    assert_equal ["1", "12"], redis.call("SMEMBERS", res)

    cmd3.clean
    assert redis.call("KEYS", nido["*"]).empty?

    cmd4 = Ohm::Command[:sinterstore, "F", "G", "H"]
    cmd5 = Ohm::Command[:sdiffstore, cmd3, cmd4]

    res = cmd5.call(nido, redis)
    assert_equal ["1"], redis.call("SMEMBERS", res)

    cmd5.clean
    assert redis.call("KEYS", nido["*"]).empty?
  end
end
