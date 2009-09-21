require File.join(File.dirname(__FILE__), "test_helper")

class IndicesTest < Test::Unit::TestCase
  setup do
    Ohm.flush
  end

  class User < Ohm::Model
    attribute :email
    attribute :update
    attribute :activation_code

    index :email
    index :email_provider
    index :working_days
    index :update
    index :activation_code

    def email_provider
      email.split("@").last
    end

    def working_days
      @working_days ||= []
    end

    def write
      self.activation_code ||= "user:#{id}"
      super
    end
  end

  context "A model with an indexed attribute" do
    setup do
      @user1 = User.create(:email => "foo")
      @user2 = User.create(:email => "bar")
      @user3 = User.create(:email => "baz qux")
    end

    should "be able to find by the given attribute" do
      assert_equal @user1, User.find(:email, "foo").first
    end

    should "return nil if no results are found" do
      assert User.find(:email, "foobar").empty?
      assert_equal nil, User.find(:email, "foobar").first
    end

    should "update indices when changing attribute values" do
      @user1.email = "baz"
      @user1.save

      assert_equal [], User.find(:email, "foo")
      assert_equal [@user1], User.find(:email, "baz")
    end

    should "remove from the index after deleting" do
      @user2.delete

      assert_equal [], User.find(:email, "bar")
    end

    should "work with attributes that contain spaces" do
      assert_equal [@user3], User.find(:email, "baz qux")
    end
  end

  context "Indexing arbitrary attributes" do
    setup do
      @user1 = User.create(:email => "foo@gmail.com")
      @user2 = User.create(:email => "bar@gmail.com")
      @user3 = User.create(:email => "bazqux@yahoo.com")
    end

    should "allow indexing by an arbitrary attribute" do
      assert_equal [@user1, @user2], User.find(:email_provider, "gmail.com").to_a.sort_by { |u| u.id }
      assert_equal [@user3], User.find(:email_provider, "yahoo.com")
    end

    should "allow indexing by an attribute that is lazily set" do
      assert_equal [@user1], User.find(:activation_code, "user:1").to_a
    end
  end

  context "Indexing enumerables" do
    setup do
      @user1 = User.create(:email => "foo@gmail.com")
      @user2 = User.create(:email => "bar@gmail.com")

      @user1.working_days << "Mon"
      @user1.working_days << "Tue"
      @user2.working_days << "Mon"
      @user2.working_days << "Wed"

      @user1.save
      @user2.save
    end

    should "index each item" do
      assert_equal [@user1, @user2], User.find(:working_days, "Mon").to_a.sort_by { |u| u.id }
    end

    # TODO If we deal with Ohm collections, the updates are atomic but the reindexing never happens.
    # One solution may be to reindex after inserts or deletes in collection.
    should "remove the indices when the object changes" do
      @user2.working_days.delete "Mon"
      @user2.save
      assert_equal [@user1], User.find(:working_days, "Mon")
    end
  end

  context "Intersection and and union" do
    class Event < Ohm::Model
      attr_writer :days

      attribute :timeline
      index :timeline
      index :days

      def days
        @days ||= []
      end
    end

    setup do
      @event1 = Event.create(:timeline => 1)
      @event2 = Event.create(:timeline => 1)
      @event3 = Event.create(:timeline => 2)
      @event1.days = [1, 2]
      @event2.days = [2, 3]
      @event3.days = [3, 4]
      @event1.save
      @event2.save
      @event3.save
    end

    should "intersect multiple sets of results" do
      Event.filter(:timeline => 1, :days => [1, 2]) do |set|
        assert_equal [@event1], set
      end
    end

    should "group multiple sets of results" do
      Event.search(:days => [1, 2]) do |set|
        assert_equal [@event1, @event2], set
      end
    end

    should "combine intersections and unions" do
      Event.search(:days => [1, 2, 3]) do |events|
        events.filter(:timeline => 1) do |result|
          assert_equal [@event1, @event2], result
        end
      end
    end

    should "work with strings that generate a new line when encoded" do
      user = User.create(:email => "foo@bar", :update => "CORRECTED - UPDATE 2-Suspected US missile strike kills 5 in Pakistan")
      assert_equal [user], User.find(:update, "CORRECTED - UPDATE 2-Suspected US missile strike kills 5 in Pakistan")
    end
  end
end
