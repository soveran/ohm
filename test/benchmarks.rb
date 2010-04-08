require "rubygems"
require "bench"
require File.dirname(__FILE__) + "/../lib/ohm"

Ohm.connect(:port => 6381)
Ohm.flush

class Event < Ohm::Model
  attribute :name
  attribute :location

  index :name
  index :location

  def validate
    assert_present :name
    assert_present :location
  end
end

i = 0

benchmark "Create Events" do
  Event.create(:name => "Redis Meetup #{i}", :location => "London #{i}")
end

benchmark "Find by indexed attribute" do
  Event.find(:name => "Redis Meetup #{i}").first
end

benchmark "Mass update" do
  Event[1].update(:name => "Redis Meetup II")
end

benchmark "Load events" do
  Event[1].name
end

run 5000
