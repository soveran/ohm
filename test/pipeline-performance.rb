# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

Ohm.flush

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

create = lambda do |i|
  User.new(:fname => "John#{i}",
           :lname => "Doe#{i}",
           :bday => Time.now.to_s,
           :gender => "Male",
           :city => "Los Angeles",
           :state => "CA",
           :country => "US",
           :zip => "90210").save
end

10.times(&create)

require "benchmark"

t1 = Benchmark.realtime do
  User.all.sort_by(:fname, :order => "DESC ALPHA").each do |user|
  end
end

t2 = Benchmark.realtime do
  ids = User.key[:all].smembers

  ids.each do |id|
    User[id]
  end
end

test "pipelined approach should be 1.5 at least times faster for 10 records" do
  assert(t2 / t1 >= 1.5)
end

90.times(&create)

t1 = Benchmark.realtime do
  User.all.sort_by(:fname, :order => "DESC ALPHA").each do |user|
  end
end

t2 = Benchmark.realtime do
  ids = User.key[:all].smembers

  ids.each do |id|
    User[id]
  end
end

test "the pipelined approach should be faster for 100 records" do
  assert(t2 > t1)
end
