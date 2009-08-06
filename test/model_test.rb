require File.join(File.dirname(__FILE__), "test_helper")

class Post < Ohm::Model
  attribute :body
  list :comments
end

class User < Ohm::Model
  attribute :email
  set :posts, Post
end

class Person < Ohm::Model
  attribute :name

  def validate
    assert_present :name
  end
end

class Event < Ohm::Model
  attribute :name
  counter :votes
  set :attendees, Person
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

    should "return the unsaved object if validation fails" do
      assert Person.create(:name => nil).kind_of?(Person)
    end
  end

  context "Finding an event" do
    setup do
      Ohm.redis.sadd("Event", 1)
      Ohm.redis.set("Event:1:name", "Concert")
    end

    should "return an instance of Event" do
      assert Event[1].kind_of?(Event)
      assert_equal 1, Event[1].id
      assert_equal "Concert", Event[1].name
    end
  end

  context "Finding a user" do
    setup do
      Ohm.redis.sadd("User:all", 1)
      Ohm.redis.set("User:1:email", "albert@example.com")
    end

    should "return an instance of User" do
      assert User[1].kind_of?(User)
      assert_equal 1, User[1].id
      assert_equal "albert@example.com", User[1].email
    end
  end

  context "Updating a user" do
    setup do
      Ohm.redis.sadd("User:all", 1)
      Ohm.redis.set("User:1:email", "albert@example.com")

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
    should "create the model if it's new" do
      event = Event.new(:name => "Foo").save
      assert_equal "Foo", Event[event.id].name
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
      set :foos
      list :bars
    end

    setup do
      @model = ModelToBeDeleted.create(:name => "Lorem")

      @model.foos << "foo"
      @model.bars << "bar"
    end

    should "delete an existing model" do
      id = @model.id

      @model.delete

      assert_nil Ohm.redis.get(ModelToBeDeleted.key(id))
      assert_nil Ohm.redis.get(ModelToBeDeleted.key(id, :name))
      assert_equal Array.new, Ohm.redis.smembers(ModelToBeDeleted.key(id, :foos))
      assert_equal Array.new, Ohm.redis.list(ModelToBeDeleted.key(id, :bars))

      assert ModelToBeDeleted.all.empty?
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

  context "Sorting" do
    should "sort all" do
      Ohm.flush
      Person.create :name => "D"
      Person.create :name => "C"
      Person.create :name => "B"
      Person.create :name => "A"

      assert_equal %w[A B C D], Person.all.sort_by(:name, :order => "ALPHA").map { |person| person.name }
    end

    should "return an empty array if there are no elements to sort" do
      Ohm.flush
      assert_equal [], Person.all.sort_by(:name)
    end

    should "return the first element sorted by id when using first" do
      Ohm.flush
      Person.create :name => "A"
      Person.create :name => "B"
      assert_equal "A", Person.all.first.name
    end

    should "return the first element sorted by name if first receives a sorting option" do
      Ohm.flush
      Person.create :name => "B"
      Person.create :name => "A"
      assert_equal "A", Person.all.first(:by => :name, :order => "ALPHA").name
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

    should "load attributes as a strings" do
      event = Event.create(:name => 1)

      assert_equal "1", Event[event.id].name
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

    should "remove an element if sent :delete" do
      @event.create
      @event.attendees << "1"
      @event.attendees << "2"
      @event.attendees << "3"
      assert_equal ["1", "2", "3"], @event.attendees.raw.sort
      @event.attendees.delete("2")
      assert_equal ["1", "3"], Event[@event.id].attendees.raw.sort
    end

    should "return true if the set includes some member" do
      @event.create
      @event.attendees << "1"
      @event.attendees << "2"
      @event.attendees << "3"
      assert @event.attendees.include?("2")
      assert_equal false, @event.attendees.include?("4")
    end

    should "return instances of the passed model if the call to all includes a class" do
      @event.create
      @person = Person.create :name => "albert"
      @event.attendees << @person.id

      assert_equal [@person], @event.attendees.all
    end

    should "insert the model instance id instead of the object if using add" do
      @event.create
      @person = Person.create :name => "albert"
      @event.attendees.add(@person)

      assert_equal [@person.id.to_s], @event.attendees.raw
    end

    should "return the size of the set" do
      @event.create
      @event.attendees << "1"
      @event.attendees << "2"
      @event.attendees << "3"
      assert_equal 3, @event.attendees.size
    end
  end

  context "Attributes of type List" do
    setup do
      @post = Post.new
      @post.body = "Hello world!"
      @post.create
    end

    should "return an array" do
      assert @post.comments.all.kind_of?(Array)
    end

    should "keep the inserting order" do
      @post.comments << "1"
      @post.comments << "2"
      @post.comments << "3"
      assert_equal ["1", "2", "3"], @post.comments.all
    end

    should "keep the inserting order after saving" do
      @post.comments << "1"
      @post.comments << "2"
      @post.comments << "3"
      @post.save
      assert_equal ["1", "2", "3"], Post[@post.id].comments.all
    end

    should "respond to each" do
      @post.comments << "1"
      @post.comments << "2"
      @post.comments << "3"

      i = 1
      @post.comments.each do |c|
        assert_equal i, c.to_i
        i += 1
      end
    end

    should "return the size of the list" do
      @post.comments << "1"
      @post.comments << "2"
      @post.comments << "3"
      assert_equal 3, @post.comments.size
    end

    should "return the last element with pop" do
      @post.comments << "1"
      @post.comments << "2"
      assert_equal "2", @post.comments.pop
      assert_equal "1", @post.comments.pop
      assert @post.comments.empty?
    end

    should "return the first element with shift" do
      @post.comments << "1"
      @post.comments << "2"
      assert_equal "1", @post.comments.shift
      assert_equal "2", @post.comments.shift
      assert @post.comments.empty?
    end

    should "push to the head of the list with unshift" do
      @post.comments.unshift "1"
      @post.comments.unshift "2"
      assert_equal "1", @post.comments.pop
      assert_equal "2", @post.comments.pop
      assert @post.comments.empty?
    end
  end

  context "Applying arbitrary transformations" do
    class Calendar < Ohm::Model
      list :holidays, lambda { |v| Date.parse(v) }
    end

    setup do
      @calendar = Calendar.create
      @calendar.holidays << "05/25/2009"
      @calendar.holidays << "07/09/2009"
    end

    should "apply a transformation" do
      assert_equal [Date.parse("2009-05-25"), Date.parse("2009-07-09")], @calendar.holidays
    end
  end

  context "Sorting lists and sets" do
    setup do
      @post = Post.create(:body => "Lorem")
      @post.comments << 2
      @post.comments << 3
      @post.comments << 1
    end

    should "sort values" do
      assert_equal %w{1 2 3}, @post.comments.sort
    end
  end

  context "Sorting lists and sets by model attributes" do
    setup do
      @event = Event.create(:name => "Ruby Tuesday")
      @event.attendees << Person.create(:name => "D").id
      @event.attendees << Person.create(:name => "C").id
      @event.attendees << Person.create(:name => "B").id
      @event.attendees << Person.create(:name => "A").id
    end

    should "sort the model instances by the values provided" do
      people = @event.attendees.sort_by(:name, :order => "ALPHA")
      assert_equal %w[A B C D], people.map { |person| person.name }
    end

    should "accept a number in the limit parameter" do
      people = @event.attendees.sort_by(:name, :limit => 2, :order => "ALPHA")
      assert_equal %w[A B], people.map { |person| person.name }
    end

    should "use the start parameter as an offset if the limit is provided" do
      people = @event.attendees.sort_by(:name, :limit => 2, :start => 1, :order => "ALPHA")
      assert_equal %w[B C], people.map { |person| person.name }
    end
  end

  context "Collections initialized with a Model parameter" do
    setup do
      @user = User.create(:email => "albert@example.com")
      @user.posts.add Post.create(:body => "D")
      @user.posts.add Post.create(:body => "C")
      @user.posts.add Post.create(:body => "B")
      @user.posts.add Post.create(:body => "A")
    end

    should "return instances of the passed model" do
      assert_equal Post, @user.posts.first.class
    end
  end

  context "Counters" do
    setup do
      @event = Event.create(:name => "Ruby Tuesday")
    end

    should "raise ArgumentError if the attribute is not a counter" do
      assert_raise ArgumentError do
        @event.incr(:name)
      end
    end

    should "be zero if not initialized" do
      assert_equal 0, @event.votes
    end

    should "be able to increment a counter" do
      @event.incr(:votes)
      assert_equal 1, @event.votes
    end

    should "be able to decrement a counter" do
      @event.decr(:votes)
      assert_equal -1, @event.votes
    end
  end

  context "Comparison" do
    setup do
      @user = User.create(:email => "foo")
    end

    should "be comparable to other instances" do
      assert_equal @user, User[@user.id]

      assert_not_equal @user, User.create
      assert_not_equal User.new, User.new
    end

    should "not be comparable to instances of other models" do
      assert_not_equal @user, Event.create(:name => "Ruby Tuesday")
    end
  end
end
