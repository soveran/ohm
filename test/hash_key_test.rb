# encoding: UTF-8

require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))

class Tag < Ohm::Model
  attribute :name
end

class HashKeyTest < Test::Unit::TestCase
  setup do
    Ohm.flush
  end
  
  test "using a new record as a hash key" do
    assert_raise Ohm::Model::MissingID do
      { Tag.new => "name" }
    end
  end
  
  test "on a persisted model" do
    tag = Tag.create(:name => "Ruby")
    reload = Tag[tag.id]

    hash = { tag => "Ruby" }
    hash[reload] = "Ruby"
    
    assert_equal 1, hash.keys.size
    assert_equal tag, hash.keys.first
    assert_equal "Ruby", hash[tag]
    assert_equal "Ruby", hash[reload]
  end
end

