require_relative "common"

1000.times do |i|
  Event.create(:name => "Redis Meetup #{i}", :location => "At my place")
end

benchmark "Delete event" do
  Event.all.each do |event|
    event.delete
  end
end

run 1
