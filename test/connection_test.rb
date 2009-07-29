require File.join(File.dirname(__FILE__), "test_helper")

class ConnectionTest < Test::Unit::TestCase
  setup do
    @options = Ohm.options
  end

  test "connects lazily" do
    assert_nothing_raised do
      Ohm.connect(:port => 1234567)
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

    assert (conn1 != conn2)
  end

  teardown do
    Ohm.connect(*@options)
  end
end
