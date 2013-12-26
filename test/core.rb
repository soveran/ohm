require_relative "helper"

class Event < Ohm::Model
  attribute :name
  attribute :location
end

test "assign attributes from the hash" do
  event = Event.new(:name => "Ruby Tuesday")
  assert_equal event.name, "Ruby Tuesday"
end

test "assign an ID and save the object" do
  event1 = Event.create(:name => "Ruby Tuesday")
  event2 = Event.create(:name => "Ruby Meetup")

  assert_equal "1", event1.id.to_s
  assert_equal "2", event2.id.to_s
end

test "save the attributes in UTF8" do
 event = Event.create(:name => "32° Kisei-sen")
 assert "32° Kisei-sen" == Event[event.id].name
end
