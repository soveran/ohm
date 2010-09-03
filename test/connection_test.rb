require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))

class ConnectionTest < Test::Unit::TestCase
  test "connects lazily" do
    assert_nothing_raised do
      Ohm.connect(:port => 9876)
    end

    assert_raises(Errno::ECONNREFUSED) do
      Ohm.redis.get "foo"
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

    assert(conn1 != conn2)
  end

  test "supports connecting by URL" do
    Ohm.connect(:url => "redis://localhost:9876")

    assert_raises(Errno::ECONNREFUSED) do
      Ohm.redis.get "foo"
    end
  end
end
