require "bench"
require_relative "../lib/ohm"

Ohm.connect(:port => 6379, :db => 15)
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
