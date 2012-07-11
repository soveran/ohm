require_relative "helper"

scope do
  setup do
    redis = Redis.connect
    redis.flushdb

    # require 'logger'
    # redis.client.logger = Logger.new(STDOUT)
    nest  = Nest.new("User:tmp", redis)

    [1, 2, 3].each { |i| redis.sadd("A", i) }
    [1, 4, 5].each { |i| redis.sadd("B", i) }

    [10, 11, 12].each { |i| redis.sadd("C", i) }
    [11, 12, 13].each { |i| redis.sadd("D", i) }
    [12, 13, 14].each { |i| redis.sadd("E", i) }

    [10, 11, 12].each { |i| redis.sadd("F", i) }
    [11, 12, 13].each { |i| redis.sadd("G", i) }
    [12, 13, 14].each { |i| redis.sadd("H", i) }

    [redis, nest]
  end

  test "special condition: single argument returns that arg" do
    assert_equal "A", Ohm::Command[:sinterstore, "A"]
  end

  test "full stack test"  do |redis, nest|
    cmd1 = Ohm::Command[:sinterstore, "A", "B"]

    res = cmd1.call(nest, redis)
    assert_equal ["1"], res.smembers

    cmd1.clean
    assert ! res.exists

    cmd2 = Ohm::Command[:sinterstore, "C", "D", "E"]
    cmd3 = Ohm::Command[:sunionstore, cmd1, cmd2]

    res = cmd3.call(nest, redis)
    assert_equal ["1", "12"], res.smembers

    cmd3.clean
    assert redis.keys(nest["*"]).empty?

    cmd4 = Ohm::Command[:sinterstore, "F", "G", "H"]
    cmd5 = Ohm::Command[:sdiffstore, cmd3, cmd4]

    res = cmd5.call(nest, redis)
    assert_equal ["1"], res.smembers

    cmd5.clean
    assert redis.keys(nest["*"]).empty?
  end
end
