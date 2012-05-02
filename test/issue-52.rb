require_relative "helper"

class Model < Ohm::Model
  attribute :hash
  index :hash

  attribute :data
end

test do
  50.times do |i|
    Ohm.flush

    Model.create(:hash => "123")

    assert_equal 1, Ohm.redis.scard("Model:all")

    Thread.new do
      a = Model.find(:hash => "123").first
      a.update(:data => "2")
    end

    sleep 0.01

    b = Model.find(:hash => "123").first

    if Ohm.redis.scard("Model:indices:hash:123") != 1
      flunk("Failed at iteration %d" % i)
    end

    assert ! b.nil?
  end
end

