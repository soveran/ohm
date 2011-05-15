# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

class Event < Ohm::Model
  attribute :name
  attribute :place
  attribute :capacity

  index :name
  index :place

  def validate
    assert_format(:name, /^\w+$/)
  end
end

class Validatable
  attr_accessor :name

  include Ohm::Validations
end

# A new model with validations
scope do
  setup do
    Event.new
  end

  # That must have a present name
  scope do
    test "not be created if the name is never assigned" do |event|
      event.create
      assert event.new?
    end

    test "not be created if the name assigned is empty" do |event|
      event.name = ""
      event.create
      assert event.new?
    end

    test "be created if the name assigned is not empty" do |event|
      event.name = "hello"
      event.create
      assert event.id
    end

    # And must have a name with only \w+
    scope do
      test "not be created if the name doesn't match /^\w+$/" do |event|
        event.name = "hello-world"
        event.create
        assert event.new?
      end
    end
  end

  # That must have a numeric attribute :capacity
  scope do
    test "fail when the value is nil" do |event|
      def event.validate
        assert_numeric :capacity
      end

      event.name = "foo"
      event.place = "bar"
      event.create

      assert event.new?
      assert [[:capacity, :not_numeric]] == event.errors
    end

    test "fail when the value is not numeric" do |event|
      def event.validate
        assert_numeric :capacity
      end

      event.name = "foo"
      event.place = "bar"
      event.capacity = "baz"
      event.create

      assert event.new?
      assert [[:capacity, :not_numeric]] == event.errors
    end

    test "succeed when the value is numeric" do |event|
      def event.validate
        assert_numeric :capacity
      end

      event.name = "foo"
      event.place = "bar"
      event.capacity = 42
      event.create

      assert event.id
    end
  end

  # That must have a unique name
  scope do
    test "fail when the value already exists" do |event|
      def event.validate
        assert_unique :name
      end

      Event.create(:name => "foo")
      event.name = "foo"
      event.create

      assert event.new?
      assert [[:name, :not_unique]] == event.errors
    end
  end

  # That must have a unique name
  scope do
    test "fail when the value already exists" do |event|

      Event.create(:name => "foo")
      event.name = "foo"
      event.create

      assert !event.new?
      assert !event.assert_unique(:name)
      assert [[:name, :not_unique]] == event.errors
    end
  end

  # That must have a unique name scoped by place
  scope do
    test "fail when the value already exists for a scoped attribute" do |event|
      def event.validate
        assert_unique [:name, :place]
      end

      Event.create(:name => "foo", :place => "bar")
      event.name = "foo"
      event.place = "bar"
      event.create

      assert event.new?
      assert [[[:name, :place], :not_unique]] == event.errors

      event.place = "baz"
      event.create

      assert event.valid?
    end
  end

  # That defines a unique validation on a non indexed attribute
  scope do
    test "raise ArgumentError" do |event|
      def event.validate
        assert_unique :capacity
      end

      assert_raise(Ohm::Model::IndexNotFound) do
        event.valid?
      end
    end
  end
end

# An existing model with a valid name
scope do
  setup do
    event = Event.create(:name => "original")
  end

  # That has the name changed
  scope do
    test "not be saved if the new name is nil" do |event|
      event.name = nil
      event.save
      assert false == event.valid?
      assert "original" == Event[event.id].name
    end

    test "not be saved if the name assigned is empty" do |event|
      event.name = ""
      event.save
      assert false == event.valid?
      assert "original" == Event[event.id].name
    end

    test "be saved if the name assigned is not empty" do |event|
      event.name = "hello"
      event.save
      assert event.valid?
      assert "hello" == Event[event.id].name
    end
  end
end

# Validations module
scope do
  setup do
    Validatable.new
  end

  # assert
  scope do
    test "add errors to a collection" do |target|
      def target.validate
        assert(false, "Something bad")
      end

      target.validate

      assert ["Something bad"] == target.errors
    end

    test "allow for nested validations" do |target|
      def target.validate
        if assert(true, "No error")
          assert(false, "Chained error")
        end

        if assert(false, "Parent error")
          assert(false, "No chained error")
        end
      end

      target.validate

      assert ["Chained error", "Parent error"] == target.errors
    end
  end

  # assert_present
  scope do
    setup do
      target = Validatable.new

      def target.validate
        assert_present(:name)
      end

      target
    end

    test "fail when the attribute is nil" do |target|
      target.validate

      assert [[:name, :not_present]] == target.errors
    end

    test "fail when the attribute is empty" do |target|
      target.name = ""
      target.validate

      assert [[:name, :not_present]] == target.errors
    end
  end
end
