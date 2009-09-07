require File.join(File.dirname(__FILE__), "test_helper")

class TestMutex < Test::Unit::TestCase
  class Person < Ohm::Model
    attribute :name
  end

  setup do
    Ohm.flush
    @p1 = Person.create :name => "Albert"
    @p2 = Person[1]
  end

  context "Using a mutex on an object" do
    should "prevent other instances of the same object from grabing a locked record" do
      t1 = t2 = nil
      p1 = Thread.new do
        @p1.mutex do
          sleep 0.4
          t1 = Time.now
        end
      end

      p2 = Thread.new do
        sleep 0.1
        @p2.mutex do
          t2 = Time.now
        end
      end

      p1.join
      p2.join
      assert t2 > t1
    end
  end
end
