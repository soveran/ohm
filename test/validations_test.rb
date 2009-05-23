require File.dirname(__FILE__) + '/test_helper'

class ValidationsTest < Test::Unit::TestCase
  class Event < Ohm::Model
    attribute :name

    def validate
      assert_format(:name, /^\w+$/)
    end
  end

  context "A new model with validations" do
    setup do
      @event = Event.new
    end

    context "That must have a present name" do
      should "not be created if the name is never assigned" do
        @event.create
        assert_nil @event.id
      end

      should "not be created if the name assigned is empty" do
        @event.name = ""
        @event.create
        assert_nil @event.id
      end

      should "be created if the name assigned is not empty" do
        @event.name = "hello"
        @event.create
        assert_not_nil @event.id
      end

      context "And must have a name with only \w+" do
        should "not be created if the name doesn't match /^\w+$/" do
          @event.name = "hello-world"
          @event.create
          assert_nil @event.id
        end
      end
    end
  end

  context "An existing model with a valid name" do
    setup do
      @event = Event.create(:name => "original")
    end

    context "That has the name changed" do
      should "not be saved if the new name is nil" do
        @event.name = nil
        @event.save
        assert_equal false, @event.valid?
        assert_equal "original", Event[@event.id].name
      end

      should "not be saved if the name assigned is empty" do
        @event.name = ""
        @event.save
        assert_equal false, @event.valid?
        assert_equal "original", Event[@event.id].name
      end

      should "be saved if the name assigned is not empty" do
        @event.name = "hello"
        @event.save
        assert @event.valid?
        assert_equal "hello", Event[@event.id].name
      end
    end
  end
end
