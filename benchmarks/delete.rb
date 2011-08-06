require File.expand_path("./common", File.dirname(__FILE__))

1000.times do |i|
  Event.create(:name => "Redis Meetup #{i}", :location => "At my place")
end

benchmark "Delete event" do
  Event.all.each do |event|
    event.delete
  end
end

run 1
