require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))

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

class Tests < Test::Unit::TestCase
  test "calls other const_missing hooks" do
    assert_equal [:Bar], $missing_constants
  end
end
