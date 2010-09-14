# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

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
