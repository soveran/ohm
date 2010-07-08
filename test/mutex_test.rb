require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))

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

    should "allow an instance to lock a record if the previous lock is expired" do
      @p1.send(:lock!)
      @p2.mutex do
        assert true
      end
    end

    should "work if two clients are fighting for the lock" do
      @p1.send(:lock!)
      @p3 = Person[1]
      @p4 = Person[1]

      assert_nothing_raised do
        p1 = Thread.new { @p1.mutex {} }
        p2 = Thread.new { @p2.mutex {} }
        p3 = Thread.new { @p3.mutex {} }
        p4 = Thread.new { @p4.mutex {} }
        p1.join
        p2.join
        p3.join
        p4.join
      end
    end

    should "yield the right result after a lock fight" do
      class Candidate < Ohm::Model
        attribute :name
        counter :votes
      end

      @candidate = Candidate.create :name => "Foo"
      @candidate.send(:lock!)

      threads = []

      n = 3
      m = 2

      n.times do |i|
        threads << Thread.new do
          m.times do |i|
            @candidate.mutex do
              sleep 0.1
              @candidate.incr(:votes)
            end
          end
        end
      end

      threads.each { |t| t.join }
      assert_equal n * m, @candidate.votes
    end
  end
end
