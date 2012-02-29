# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

prepare.clear

test "should provide pattern matching" do
  assert(Ohm::Pattern[1, Fixnum] === [1, 2])
  assert(Ohm::Pattern[String, Array] === ["foo", ["bar"]])
end
