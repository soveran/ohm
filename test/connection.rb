# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

unless defined?(Redic::CannotConnectError)
  Redic::CannotConnectError = Errno::ECONNREFUSED
end

prepare.clear

test "connects lazily" do
  Ohm.connect("redis://127.0.0.1:9876")

  begin
    Ohm.redis.call("GET", "foo")
  rescue => e
    assert [Errno::ECONNREFUSED, Errno::EINVAL].include?(e.class)
  end
end

test "provides a separate connection for each thread" do
  assert Ohm.redis == Ohm.redis

  conn1, conn2 = nil

  threads = []

  threads << Thread.new do
    conn1 = Ohm.redis
  end

  threads << Thread.new do
    conn2 = Ohm.redis
  end

  threads.each { |t| t.join }

  assert conn1 != conn2
end

test "supports connecting by URL" do
  Ohm.connect("redis://localhost:9876")

  begin
    Ohm.redis.call("GET", "foo")
  rescue => e
    assert [Errno::EINVAL, Errno::ECONNREFUSED].include?(e.class)
  end
end

setup do
  Ohm.connect("redis://localhost:6379/0")
end

test "connection class" do
  conn = Ohm::Connection.new(:foo, "redis://localhost:6379/0")

  assert conn.redis.kind_of?(Redic)
end

test "issue #46" do
  class B < Ohm::Model
    connect("redis://localhost:6379/15")
  end

  # We do this since we did prepare.clear above.
  B.db.call("FLUSHALL")

  b1, b2 = nil, nil

  Thread.new { b1 = B.create }.join
  Thread.new { b2 = B.create }.join

  assert_equal [b1, b2], B.all.sort.to_a
end

test "model can define its own connection" do
  class B < Ohm::Model
    connect("redis://localhost:6379/1")
  end

  assert_equal B.conn.url,   "redis://localhost:6379/1"
  assert_equal Ohm.conn.url, "redis://localhost:6379/0"
end

test "model inherits Ohm.redis connection by default" do
  Ohm.connect("redis://localhost:9876")
  class C < Ohm::Model
  end

  assert_equal C.conn.url, Ohm.conn.url
end
