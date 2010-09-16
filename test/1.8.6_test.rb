# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

prepare.clear

test "String#lines should return the parts when separated with \\n" do
  assert ["a\n", "b\n", "c\n"] == "a\nb\nc\n".lines.to_a
end

test "String#lines return the parts when separated with \\r\\n" do
  assert ["a\r\n", "b\r\n", "c\r\n"] == "a\r\nb\r\nc\r\n".lines.to_a
end

test "String#lines accept a record separator" do
  assert ["ax", "bx", "cx"] == "axbxcx".lines("x").to_a
end

test "String#lines execute the passed block" do
  lines = ["a\r\n", "b\r\n", "c\r\n"]

  "a\r\nb\r\nc\r\n".lines do |line|
    assert lines.shift == line
  end
end
