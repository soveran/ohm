require "rubygems"
require "bench"
require File.dirname(__FILE__) + "/../lib/ohm"
require "redis"

Ohm.connect(:port => 6381)
Ohm.flush

$r = Redis.new(:port => 6381)

class Event < Ohm::Model
  attribute :name
  set :attendees

  def validate
    assert_present :name
  end
end

event = Event.create(:name => "Ruby Tuesday")
array = []

benchmark "add to set with ohm redis" do
  Ohm.redis.sadd("foo", 1)
end

benchmark "add to set with redis" do
  $r.set_add("foo", 1)
end

benchmark "add to set with ohm" do
  event.attendees << 1
end

Ohm.redis.sadd("bar", 1)
Ohm.redis.sadd("bar", 2)

benchmark "retrieve a set of two members with ohm redis" do
  Ohm.redis.sadd("bar", 3)
  Ohm.redis.srem("bar", 3)
  Ohm.redis.smembers("bar")
end

$r.set_add("bar", 1)
$r.set_add("bar", 2)

benchmark "retrieve a set of two members with redis" do
  $r.set_add("bar", 3)
  $r.set_delete("bar", 3)
  $r.set_members("bar")
end

Ohm.redis.del("Event:#{event.id}:attendees")
$r.delete("Event:#{event.id}:attendees")

event.attendees << 1
event.attendees << 2

benchmark "retrieve a set of two members with ohm" do
  event.attendees << 3
  event.attendees.delete(3)
  event.attendees
end

benchmark "retrieve membership status and set count" do
  Ohm.redis.scard("bar")
  Ohm.redis.sismember("bar", "1")
end

benchmark "retrieve set count" do
  Ohm.redis.scard("bar").zero?
end

benchmark "retrieve membership status" do
  Ohm.redis.sismember("bar", "1")
end

run 10_000
