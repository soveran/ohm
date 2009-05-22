require "rubygems"
require "ruby-debug"
require "contest"
require File.dirname(__FILE__) + "/../lib/ohm"

$redis = Redis.new(:port => 6381)
$redis.flush_db

class Event < Ohm::Model
  attribute :name
  set :attendees
end

class User < Ohm::Model
  attribute :email
end

class Post < Ohm::Model
  attribute :body
  list :comments
end

class TestRedis < Test::Unit::TestCase
  context "An event initialized with a hash of attributes" do
    should "assign the passed attributes" do
      event = Event.new(:name => "Ruby Tuesday")
      assert_equal event.name, "Ruby Tuesday"
    end
  end

  context "An event created from a hash of attributes" do
    should "assign an id and save the object" do
      event1 = Event.create(:name => "Ruby Tuesday")
      event2 = Event.create(:name => "Ruby Meetup")
      assert_equal event1.id + 1, event2.id
    end
  end

  context "Finding an event" do
    setup do
      $redis["Event:1"] = true
      $redis["Event:1:name"] = "Concert"
    end

    should "return an instance of Event" do
      assert Event[1].kind_of?(Event)
      assert_equal 1, Event[1].id
      assert_equal "Concert", Event[1].name
    end
  end

  context "Finding a user" do
    setup do
      $redis["User:1"] = true
      $redis["User:1:email"] = "albert@example.com"
    end

    should "return an instance of User" do
      assert User[1].kind_of?(User)
      assert_equal 1, User[1].id
      assert_equal "albert@example.com", User[1].email
    end
  end

  context "Updating a user" do
    setup do
      $redis["User:1"] = true
      $redis["User:1:email"] = "albert@example.com"

      @user = User[1]
    end

    should "change its attributes" do
      @user.email = "maria@example.com"
      assert_equal "maria@example.com", @user.email
    end

    should "save the new values" do
      @user.email = "maria@example.com"
      @user.save

      @user.email = "maria@example.com"
      @user.save

      assert_equal "maria@example.com", User[1].email
    end
  end

  context "Creating a new model" do
    should "assign a new id to the event" do
      event1 = Event.new
      event1.create

      event2 = Event.new
      event2.create

      assert event1.id
      assert_equal event1.id + 1, event2.id
    end
  end

  context "Saving a model" do
    should "not save a new model" do
      assert_raise Ohm::Model::ModelIsNew do
        Event.new.save
      end
    end

    should "save it only if it was previously created" do
      event = Event.new
      event.name = "Lorem ipsum"
      event.create

      event.name = "Lorem"
      event.save

      assert_equal "Lorem", Event[event.id].name
    end
  end

  context "Delete" do
    class ModelToBeDeleted < Ohm::Model
      attribute :name
    end

    setup do
      @model = ModelToBeDeleted.create(:name => "Lorem")
    end

    should "delete an existing model" do
      id = @model.id

      @model.delete

      assert_nil $redis[ModelToBeDeleted.key(id)]
      assert_nil $redis[ModelToBeDeleted.key(id, :name)]

      assert ModelToBeDeleted.all.empty?
    end

    should "reset the ID on the instance" do
      id = @model.id

      @model.delete

      assert_nil @model.id

      assert_not_equal id, @model.create.id
    end
  end

  context "Listing" do
    should "find all" do
      event1 = Event.new
      event1.name = "Ruby Meetup"
      event1.create

      event2 = Event.new
      event2.name = "Ruby Tuesday"
      event2.create

      all = Event.all

      assert all.detect {|e| e.name == "Ruby Meetup" }
      assert all.detect {|e| e.name == "Ruby Tuesday" }
    end
  end

  context "Loading attributes" do
    setup do
      event = Event.new
      event.name = "Ruby Tuesday"
      @id = event.create.id
    end

    should "load attributes lazily" do
      event = Event[@id]

      assert_nil event.send(:instance_variable_get, "@name")
      assert_equal "Ruby Tuesday", event.name
    end
  end

  context "Attributes of type Set" do
    setup do
      @event = Event.new
      @event.name = "Ruby Tuesday"
    end

    should "not be available if the model is new" do
      assert_raise Ohm::Model::ModelIsNew do
        @event.attendees << 1
      end
    end

    should "return an array if the model exists" do
      @event.create
      assert @event.attendees.kind_of?(Array)
    end

    should "remove an element if sent :delete" do
      @event.create
      @event.attendees << "1"
      @event.attendees << "2"
      @event.attendees << "3"
      assert_equal ["1", "2", "3"], @event.attendees
      @event.attendees.delete("2")
      assert_equal ["1", "3"], Event[@event.id].attendees
    end
  end

  context "Attributes of type List" do
    setup do
      @post = Post.new
      @post.body = "Hello world!"
      @post.create
    end

    should "return an array" do
      assert @post.comments.kind_of?(Array)
    end

    should "keep the inserting order" do
      @post.comments << "1"
      @post.comments << "2"
      @post.comments << "3"
      assert_equal ["1", "2", "3"], @post.comments
    end

    should "keep the inserting order after saving" do
      @post.comments << "1"
      @post.comments << "2"
      @post.comments << "3"
      @post.save
      assert_equal ["1", "2", "3"], Post[@post.id].comments
    end
  end
end
