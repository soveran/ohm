# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

prepare.clear

test "connects lazily" do
  Ohm.connect(:port => 9876)

  begin
    Ohm.redis.get "foo"
  rescue => e
    assert Errno::ECONNREFUSED == e.class
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
  Ohm.connect(:url => "redis://localhost:9876")

  begin
    Ohm.redis.get "foo"
  rescue => e
    assert Errno::ECONNREFUSED == e.class
  end
end

setup do
  Ohm.connect(:url => "redis://localhost:6379/0")
end

test "connection class" do
  conn = Ohm::Connection.new(:foo, :url => "redis://localhost:6379/0")

  assert conn.redis.kind_of?(Redis)
end

test "model can define its own connection" do
  class B < Ohm::Model
    connect(:url => "redis://localhost:6379/1")
  end

  assert_equal B.conn.options,   {:url=>"redis://localhost:6379/1"}
  assert_equal Ohm.conn.options, {:url=>"redis://localhost:6379/0"}
end

test "model inherits Ohm.redis connection by default" do
  Ohm.connect(:url => "redis://localhost:9876")
  class C < Ohm::Model
  end

  assert_equal C.conn.options, Ohm.conn.options
end
