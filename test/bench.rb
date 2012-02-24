require File.expand_path("../lib/ohm", File.dirname(__FILE__))

Ohm.redis.flushdb

class User < Ohm::Model
  attribute :fname
  attribute :lname
  attribute :bday
  attribute :gender
  attribute :city
  attribute :state
  attribute :country
  attribute :zip
end

100.times do |i|
  user = User.new(fname: "John#{i}",
                  lname: "Doe#{i}",
                  bday: Time.now.to_s,
                  gender: "Male",
                  city: "Los Angeles",
                  state: "CA",
                  country: "US",
                  zip: "90210").save
end

require "benchmark"

t1 = Benchmark.realtime do
  User.all.sort_by(:fname, order: "DESC ALPHA").each do |user|
  end
end

t2 = Benchmark.realtime do
  ids = User.key[:all].smembers

  ids.each do |id|
    User[id]
  end
end

puts t1
puts t2
puts t2 / t1
