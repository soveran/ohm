require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))

class TestArray < Test::Unit::TestCase
  test "should provide pattern matching" do
    assert([1, Fixnum] === [1, 2])
    assert([String, Array] === ["foo", ["bar"]])
  end

  test "should preserve the original behavior" do
    assert([:foo, :bar] === [:foo, :bar])
    assert([1, 2] === [1, 2])
  end
end
