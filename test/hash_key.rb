# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

class Tag < Ohm::Model
  attribute :name
end

test "using a new record as a hash key" do
  tag = Tag.new
  hash = { tag => "Ruby" }

  assert "Ruby" == hash[tag]
  assert hash[Tag.new].nil?
end

test "on a persisted model" do
  tag = Tag.create(:name => "Ruby")

  assert "Ruby" == { tag => "Ruby" }[tag]
end

test "on a reloaded model" do
  tag = Tag.create(:name => "Ruby")
  hash = { tag => "Ruby" }

  tag = Tag[tag.id]
  assert "Ruby" == hash[tag]
end

test "on attributes class method" do
  assert [:name] == Tag.attributes
end
