require "rubygems"
require "bench"
require File.dirname(__FILE__) + "/../lib/ohm"

$redis = Redis.new(:port => 6381)
$redis.flush_db

class Event < Ohm::Model
  attribute :name
  set :attendees

  def validate
    assert_present :name
  end
end

event = Event.create(:name => "Ruby Tuesday")
array = []

benchmark "redis add to set" do
  $redis.set_add("foo", 1)
end

benchmark "ohm add to set" do
  event.attendees << 1
end

benchmark "ruby array push" do
  array.push(1)
end

$redis.set_add("bar", 1)
$redis.set_add("bar", 2)

benchmark "retrieve a set of two members" do
  $redis.set_members("bar")
end

benchmark "retrieve membership status and set count" do
  $redis.set_count("bar")
  $redis.set_member?("bar", "1")
end

benchmark "retrieve set count" do
  $redis.set_count("bar").zero?
end

benchmark "retrieve membership status" do
  $redis.set_member?("bar", "1")
end

run 20_000
