require_relative "common"

benchmark "Create Events" do
  i = Sequence[:events].succ!

  Event.create(:name => "Redis Meetup #{i}", :location => "London #{i}")
end

benchmark "Find by indexed attribute" do
  Event.find(:name => "Redis Meetup 1").first
end

benchmark "Mass update" do
  Event[1].update(:name => "Redis Meetup II")
end

benchmark "Load events" do
  Event[1].name
end

run 5000
