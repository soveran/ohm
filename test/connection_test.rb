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

test "Model.db is the same as Ohm.redis by default" do
  class U < Ohm::Model
  end

  assert_equal U.db.object_id, Ohm.redis.object_id
end

test "provides a unique Model.db connection in one thread" do
  class U < Ohm::Model
  end

  U.connect(db: 9876)

  r1 = U.db
  r2 = U.db

  assert_equal r1.object_id, r2.object_id
end

test "provides distinct Model.db connections per thread" do
  class U < Ohm::Model
  end

  U.connect(db: 9876)

  r1 = nil
  r2 = nil

  Thread.new { r1 = U.db }.join
  Thread.new { r2 = U.db }.join

  assert r1.object_id != r2.object_id
end

test "busts threaded cache when doing Model.connect" do
  class U < Ohm::Model
  end

  U.connect(db: 9876)
  r1 = U.db

  U.connect(db: 9876)
  r2 = U.db

  assert r1.object_id != r2.object_id
end

test "disallows the non-thread safe writing of Model.db" do
  class U < Ohm::Model
  end

  assert_raise NoMethodError do
    U.db = Redis.connect
  end
end
