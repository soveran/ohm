# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

class Ad < Ohm::Model
  counter :hits
end

test do
  instance1 = Ad.create
  instance1.incr :hits

  instance2 = Ad[instance1.id]

  instance1.incr :hits
  instance1.incr :hits

  instance2.save

  instance1 = Ad[instance1.id]
  assert_equal 3, instance1.hits
end