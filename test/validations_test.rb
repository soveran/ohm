require File.dirname(__FILE__) + '/test_helper'

class ValidationsTest < Test::Unit::TestCase
  class Event < Ohm::Model
    attribute :name

    def validate
      false
    end
  end

  context "A model with validations" do
    should "not be created if it doesn't validate" do
      event = Event.new

      event.create

      assert_nil event.id
    end
  end
end
