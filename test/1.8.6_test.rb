require File.join(File.dirname(__FILE__), "test_helper")

class TestString < Test::Unit::TestCase
  context "String#lines" do
    should "return the parts when separated with \\n" do
      assert_equal ["a\n", "b\n", "c\n"], "a\nb\nc\n".lines.to_a
    end

    should "return the parts when separated with \\r\\n" do
      assert_equal ["a\r\n", "b\r\n", "c\r\n"], "a\r\nb\r\nc\r\n".lines.to_a
    end

    should "accept a record separator" do
      assert_equal ["ax", "bx", "cx"], "axbxcx".lines("x").to_a
    end

    should "execute the passed block" do
      lines = ["a\r\n", "b\r\n", "c\r\n"]

      "a\r\nb\r\nc\r\n".lines do |line|
        assert_equal lines.shift, line
      end
    end
  end
end
