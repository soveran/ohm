# encoding: UTF-8

require "./test/helper"

$missing_constants = []

class Object
  def self.const_missing(name)
    $missing_constants << name
    super(name)
  end
end

class Foo < Ohm::Model
  set :bars, Bar
end

test "calls other const_missing hooks" do
  assert [:Bar] == $missing_constants
end
