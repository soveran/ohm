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

  context "Validations module" do
    class Validatable
      attr_accessor :name

      include Ohm::Validations
    end
    
    setup do
      @target = Validatable.new
    end

    context "assert" do
      should "add errors to a collection" do
        def @target.validate
          assert(false, "Something bad")
        end

        @target.validate

        assert_equal ["Something bad"], @target.errors
      end

      should "allow for nested validations" do
        def @target.validate
          if assert(true, "No error")
            assert(false, "Chained error")
          end

          if assert(false, "Parent error")
            assert(false, "No chained error")
          end
        end

        @target.validate

        assert_equal ["Chained error", "Parent error"], @target.errors
      end
    end

    context "assert_present" do
      setup do
        def @target.validate
          assert_present(:name)
        end
      end

      should "fail when the attribute is nil" do
        @target.validate

        assert_equal [[:name, :nil]], @target.errors
      end
      
      should "fail when the attribute is empty" do
        @target.name = ""
        @target.validate

        assert_equal [[:name, :empty]], @target.errors
      end
    end
    
    context "assert_not_nil" do
      should "fail when the attribute is nil" do
        def @target.validate
          assert_not_nil(:name)
        end

        @target.validate

        assert_equal [[:name, :nil]], @target.errors
        
        @target.errors.clear
        @target.name = ""
        @target.validate

        assert_equal [], @target.errors
      end
    end
  end
end
