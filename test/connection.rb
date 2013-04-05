# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

unless defined?(Redic::CannotConnectError)
  Redic::CannotConnectError = Errno::ECONNREFUSED
end

test "model can define its own connection" do
  class B < Ohm::Model
    self.redis = Redic.new("redis://localhost:6379/1")
  end

  assert B.redis.url != Ohm.redis.url
end

test "model inherits Ohm.redis connection by default" do
  class C < Ohm::Model
  end

  assert_equal C.redis.url, Ohm.redis.url
end
