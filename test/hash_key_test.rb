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
    tag = Tag.new
    hash = { tag => "Ruby" }

    assert_equal "Ruby", hash[tag]
    assert_nil hash[Tag.new]
  end

  test "on a persisted model" do
    tag = Tag.create(:name => "Ruby")

    assert_equal "Ruby", { tag => "Ruby" }[tag]
  end

  test "on a reloaded model" do
    tag = Tag.create(:name => "Ruby")
    hash = { tag => "Ruby" }

    tag = Tag[tag.id]
    assert_equal "Ruby", hash[tag]
  end
end

