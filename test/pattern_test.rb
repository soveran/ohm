require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))

class TestArray < Test::Unit::TestCase
  test "should provide pattern matching" do
    assert(Ohm::Pattern[1, Fixnum] === [1, 2])
    assert(Ohm::Pattern[String, Array] === ["foo", ["bar"]])
  end
end
