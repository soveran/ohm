require "./test/helper"

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

def context(*a); yield; end

context "A new model with validations" do
  setup do
    Ohm.flush
    @event = Event.new
  end

  context "That must have a present name" do
    test "not be created if the name is never assigned" do
      @event.create
      assert @event.new?
    end

    test "not be created if the name assigned is empty" do
      @event.name = ""
      @event.create
      assert @event.new?
    end

    test "be created if the name assigned is not empty" do
      @event.name = "hello"
      @event.create
      assert @event.id
    end

    context "And must have a name with only \w+" do
      test "not be created if the name doesn't match /^\w+$/" do
        @event.name = "hello-world"
        @event.create
        assert @event.new?
      end
    end
  end

  context "That must have a numeric attribute :capacity" do
    test "fail when the value is nil" do
      def @event.validate
        assert_numeric :capacity
      end

      @event.name = "foo"
      @event.place = "bar"
      @event.create

      assert @event.new?
      assert [[:capacity, :not_numeric]] == @event.errors
    end

    test "fail when the value is not numeric" do
      def @event.validate
        assert_numeric :capacity
      end

      @event.name = "foo"
      @event.place = "bar"
      @event.capacity = "baz"
      @event.create

      assert @event.new?
      assert [[:capacity, :not_numeric]] == @event.errors
    end

    test "succeed when the value is numeric" do
      def @event.validate
        assert_numeric :capacity
      end

      @event.name = "foo"
      @event.place = "bar"
      @event.capacity = 42
      @event.create

      assert @event.id
    end
  end

  context "That must have a unique name" do
    test "fail when the value already exists" do
      def @event.validate
        assert_unique :name
      end

      Event.create(:name => "foo")
      @event.name = "foo"
      @event.create

      assert @event.new?
      assert [[:name, :not_unique]] == @event.errors
    end
  end

  context "That must have a unique name scoped by place" do
    test "fail when the value already exists for a scoped attribute" do
      def @event.validate
        assert_unique [:name, :place]
      end

      Event.create(:name => "foo", :place => "bar")
      @event.name = "foo"
      @event.place = "bar"
      @event.create

      assert @event.new?
      assert [[[:name, :place], :not_unique]] == @event.errors

      @event.place = "baz"
      @event.create

      assert @event.valid?
    end
  end

  context "That defines a unique validation on a non indexed attribute" do
    test "raise ArgumentError" do
      def @event.validate
        assert_unique :capacity
      end

      assert_raise(Ohm::Model::IndexNotFound) do
        @event.valid?
      end
    end
  end
end

context "An existing model with a valid name" do
  setup do
    @event = Event.create(:name => "original")
  end

  context "That has the name changed" do
    test "not be saved if the new name is nil" do
      @event.name = nil
      @event.save
      assert false == @event.valid?
      assert "original" == Event[@event.id].name
    end

    test "not be saved if the name assigned is empty" do
      @event.name = ""
      @event.save
      assert false == @event.valid?
      assert "original" == Event[@event.id].name
    end

    test "be saved if the name assigned is not empty" do
      @event.name = "hello"
      @event.save
      assert @event.valid?
      assert "hello" == Event[@event.id].name
    end
  end
end

context "Validations module" do
  setup do
    Ohm.flush
    @target = Validatable.new
  end

  context "assert" do
    test "add errors to a collection" do
      def @target.validate
        assert(false, "Something bad")
      end

      @target.validate

      assert ["Something bad"] == @target.errors
    end

    test "allow for nested validations" do
      def @target.validate
        if assert(true, "No error")
          assert(false, "Chained error")
        end

        if assert(false, "Parent error")
          assert(false, "No chained error")
        end
      end

      @target.validate

      assert ["Chained error", "Parent error"] == @target.errors
    end
  end

  context "assert_present" do
    setup do
      Ohm.flush

      @target = Validatable.new

      def @target.validate
        assert_present(:name)
      end
    end

    test "fail when the attribute is nil" do
      @target.validate

      assert [[:name, :not_present]] == @target.errors
    end

    test "fail when the attribute is empty" do
      @target.name = ""
      @target.validate

      assert [[:name, :not_present]] == @target.errors
    end
  end
end
