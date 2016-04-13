require "bench"
require_relative "../lib/ohm"

Ohm.redis = Redic.new("redis://127.0.0.1:6379/15")
Ohm.flush

class Event < Ohm::Model
  attribute :name
  attribute :location

  index :name
  index :location
end

class Sequence
  def initialize
    @value = 0
  end

  def succ!
    Thread.exclusive { @value += 1 }
  end

  def self.[](name)
    @@sequences ||= Hash.new { |hash, key| hash[key] = Sequence.new }
    @@sequences[name]
  end
end
