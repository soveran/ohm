# encoding: UTF-8

require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))
require "ostruct"
require "json"

class Post < Ohm::Model
  attribute :body
  list :comments
  list :related, Post
end

class User < Ohm::Model
  attribute :email
  set :posts, Post
end

class Person < Ohm::Model
  attribute :name
  index :initial

  def validate
    assert_present :name
  end

  def initial
    name[0, 1].upcase
  end
end

class Event < Ohm::Model
  attribute :name
  counter :votes
  set :attendees, Person

  attribute :slug

  def write
    self.slug = name.to_s.downcase
    super
  end
end

class ModelTest < Test::Unit::TestCase
  setup do
    Ohm.flush
  end

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

      assert_equal "1", event1.id
      assert_equal "2", event2.id
    end

    should "return the unsaved object if validation fails" do
      assert Person.create(:name => nil).kind_of?(Person)
    end
  end

  context "An event updated from a hash of attributes" do
    class Meetup < Ohm::Model
      attribute :name
      attribute :location

      def validate
        assert_present :name
      end
    end

    should "assign an id and save the object" do
      event = Meetup.create(:name => "Ruby Tuesday")
      event.update(:name => "Ruby Meetup")
      assert_equal "Ruby Meetup", event.name
    end

    should "return false if the validation fails" do
      event = Meetup.create(:name => "Ruby Tuesday")
      assert !event.update(:name => nil)
    end

    should "save the attributes in UTF8" do
     event = Meetup.create(:name => "32° Kisei-sen")
     assert_equal "32° Kisei-sen", Meetup[event.id].name
    end

    should "delete the attribute if set to nil" do
      event = Meetup.create(:name => "Ruby Tuesday", :location => "Los Angeles")
      assert_equal "Los Angeles", Meetup[event.id].location
      assert event.update(:location => nil)
      assert_equal nil, Meetup[event.id].location
    end

    should "delete the attribute if set to an empty string" do
      event = Meetup.create(:name => "Ruby Tuesday", :location => "Los Angeles")
      assert_equal "Los Angeles", Meetup[event.id].location
      assert event.update(:location => "")
      assert_equal nil, Meetup[event.id].location
    end
  end

  context "Model definition" do
    should "not raise if an attribute is redefined" do
      assert_nothing_raised do
        class RedefinedModel < Ohm::Model
          attribute :name
          attribute :name
        end
      end
    end

    should "not raise if a counter is redefined" do
      assert_nothing_raised do
        class RedefinedModel < Ohm::Model
          counter :age
          counter :age
        end
      end
    end

    should "not raise if a list is redefined" do
      assert_nothing_raised do
        class RedefinedModel < Ohm::Model
          list :todo
          list :todo
        end
      end
    end

    should "not raise if a set is redefined" do
      assert_nothing_raised do
        class RedefinedModel < Ohm::Model
          set :friends
          set :friends
        end
      end
    end

    should "not raise if a collection is redefined" do
      assert_nothing_raised do
        class RedefinedModel < Ohm::Model
          list :toys
          set :toys
        end
      end
    end

    should "not raise if a index is redefined" do
      assert_nothing_raised do
        class RedefinedModel < Ohm::Model
          attribute :color
          index :color
          index :color
        end
      end
    end
  end

  context "Finding an event" do
    setup do
      Ohm.redis.sadd("Event:all", 1)
      Ohm.redis.hset("Event:1", "name", "Concert")
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
      Ohm.redis.hset("User:1", "email", "albert@example.com")
    end

    should "return an instance of User" do
      assert User[1].kind_of?(User)
      assert_equal 1, User[1].id
      assert_equal "albert@example.com", User[1].email
    end

    should "allow to map ids to models" do
      assert_equal [User[1]], [1].map(&User)
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

      assert !event1.new?
      assert !event2.new?

      assert_equal "1", event1.id
      assert_equal "2", event2.id
    end
  end

  context "Saving a model" do
    should "create the model if it is new" do
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

    should "allow to hook into write" do
      event = Event.create(:name => "Foo")

      assert_equal "foo", event.slug
    end
  end

  context "Delete" do
    should "delete an existing model" do
      class ModelToBeDeleted < Ohm::Model
        attribute :name
        set :foos
        list :bars
      end

      @model = ModelToBeDeleted.create(:name => "Lorem")

      @model.foos << "foo"
      @model.bars << "bar"

      id = @model.id

      @model.delete

      assert_nil Ohm.redis.get(ModelToBeDeleted.key(id))
      assert_nil Ohm.redis.get(ModelToBeDeleted.key(id, :name))
      assert_equal Array.new, Ohm.redis.smembers(ModelToBeDeleted.key(id, :foos))
      assert_equal Array.new, Ohm.redis.lrange(ModelToBeDeleted.key(id, :bars), 0, -1)

      assert ModelToBeDeleted.all.empty?
    end

    should "be no leftover keys" do
      class ::Foo < Ohm::Model
        attribute :name
        index :name
      end

      assert_equal [], Ohm.redis.keys("*")

      Foo.create(:name => "Bar")

      assert_equal ["Foo:1:_indices", "Foo:1", "Foo:all", "Foo:id", "Foo:name:QmFy"].sort, Ohm.redis.keys("*").sort

      Foo[1].delete

      assert_equal ["Foo:id"], Ohm.redis.keys("*")
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
      Person.create :name => "D"
      Person.create :name => "C"
      Person.create :name => "B"
      Person.create :name => "A"

      assert_equal %w[A B C D], Person.all.sort_by(:name, :order => "ALPHA").map { |person| person.name }
    end

    should "return an empty array if there are no elements to sort" do
      assert_equal [], Person.all.sort_by(:name)
    end

    should "return the first element sorted by id when using first" do
      Person.create :name => "A"
      Person.create :name => "B"
      assert_equal "A", Person.all.first.name
    end

    should "return the first element sorted by name if first receives a sorting option" do
      Person.create :name => "B"
      Person.create :name => "A"
      assert_equal "A", Person.all.first(:by => :name, :order => "ALPHA").name
    end

    should "return attribute values when the get parameter is specified" do
      Person.create :name => "B"
      Person.create :name => "A"

      assert_equal "A", Person.all.sort_by(:name, :get => :name, :order => "ALPHA").first
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
      @person1 = Person.create(:name => "Albert")
      @person2 = Person.create(:name => "Bertrand")
      @person3 = Person.create(:name => "Charles")

      @event = Event.new
      @event.name = "Ruby Tuesday"
    end

    should "not be available if the model is new" do
      assert_raise Ohm::Model::MissingID do
        @event.attendees << Person.new
      end
    end

    should "remove an element if sent :delete" do
      @event.create
      @event.attendees << @person1
      @event.attendees << @person2
      @event.attendees << @person3
      assert_equal ["1", "2", "3"], @event.attendees.raw.sort
      @event.attendees.delete(@person2)
      assert_equal ["1", "3"], Event[@event.id].attendees.raw.sort
    end

    should "return true if the set includes some member" do
      @event.create
      @event.attendees << @person1
      @event.attendees << @person2
      assert @event.attendees.include?(@person2)
      assert !@event.attendees.include?(@person3)
    end

    should "return instances of the passed model" do
      @event.create
      @event.attendees << @person1

      assert_equal [@person1], @event.attendees.all
      assert_equal @person1, @event.attendees[0]
    end

    should "return the size of the set" do
      @event.create
      @event.attendees << @person1
      @event.attendees << @person2
      @event.attendees << @person3
      assert_equal 3, @event.attendees.size
    end

    should "empty the set" do
      @event.create
      @event.attendees << @person1

      @event.attendees.clear

      assert @event.attendees.empty?
    end

    should "replace the values in the set" do
      @event.create
      @event.attendees << @person1

      assert_equal [@person1], @event.attendees.all

      @event.attendees.replace([@person2, @person3])

      assert_equal [@person2, @person3], @event.attendees.sort
    end

    should "filter elements" do
      @event.create
      @event.attendees.add(@person1)
      @event.attendees.add(@person2)

      assert_equal [@person1], @event.attendees.find(:initial => "A").all
      assert_equal [@person2], @event.attendees.find(:initial => "B").all
      assert_equal [],    @event.attendees.find(:initial => "Z").all
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

    should "append elements with push" do
      @post.comments.push "1"
      @post.comments << "2"

      assert_equal ["1", "2"], @post.comments.all
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

    should "empty the list" do
      @post.comments.unshift "1"
      @post.comments.clear

      assert @post.comments.empty?
    end

    should "replace the values in the list" do
      @post.comments.replace(["1", "2"])

      assert_equal ["1", "2"], @post.comments
    end

    should "add models" do
      @post.related.add(Post.create(:body => "Hello"))

      assert_equal ["2"], @post.related.raw
    end

    should "find elements in the list" do
      another_post = Post.create

      @post.related.add(another_post)

      assert  @post.related.include?(another_post)
      assert !@post.related.include?(Post.create)
    end

    should "unshift models" do
      @post.related.unshift(Post.create(:body => "Hello"))
      @post.related.unshift(Post.create(:body => "Goodbye"))

      assert_equal ["3", "2"], @post.related.raw

      assert_equal "3", @post.related.shift.id

      assert_equal "2", @post.related.pop.id

      assert_nil @post.related.pop
    end
  end

  context "Applying arbitrary transformations" do
    require "date"

    class MyActiveRecordModel
      def self.find(id)
        return new if id.to_i == 1
      end

      def id
        1
      end

      def ==(other)
        id == other.id
      end
    end

    class ::Calendar < Ohm::Model
      list :holidays, lambda { |v| Date.parse(v) }
      list :subscribers, lambda { |id| MyActiveRecordModel.find(id) }
      list :appointments, Appointment
    end

    class ::Appointment < Ohm::Model
      attribute :text
      reference :subscriber, lambda { |id| MyActiveRecordModel.find(id) }
    end

    setup do
      @calendar = Calendar.create

      @calendar.holidays.raw << "2009-05-25"
      @calendar.holidays.raw << "2009-07-09"

      @calendar.subscribers << MyActiveRecordModel.find(1)
    end

    should "apply a transformation" do
      assert_equal [Date.new(2009, 5, 25), Date.new(2009, 7, 9)], @calendar.holidays.all

      assert_equal ["1"], @calendar.subscribers.raw.all
      assert_equal [MyActiveRecordModel.find(1)], @calendar.subscribers.all
    end

    should "allow lambdas in references" do
      appointment = Appointment.create(:subscriber => MyActiveRecordModel.find(1))
      assert_equal MyActiveRecordModel.find(1), appointment.subscriber
    end

    should "work with models too" do
      @calendar.appointments.add(Appointment.create(:text => "Meet with Bertrand"))

      assert_equal [Appointment[1]], Calendar[1].appointments.sort
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
      @event.attendees << Person.create(:name => "D")
      @event.attendees << Person.create(:name => "C")
      @event.attendees << Person.create(:name => "B")
      @event.attendees << Person.create(:name => "A")
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

      @event.incr(:votes, 2)
      assert_equal 3, @event.votes
    end

    should "be able to decrement a counter" do
      @event.decr(:votes)
      assert_equal -1, @event.votes

      @event.decr(:votes, 2)
      assert_equal -3, @event.votes
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

    should "be comparable to non-models" do
      assert_not_equal @user, 1
      assert_not_equal @user, true

      # Not equal although the other object responds to #key.
      assert_not_equal @user, OpenStruct.new(:key => @user.send(:key))
    end
  end

  context "Debugging" do
    class ::Bar < Ohm::Model
      attribute :name
      counter :visits
      set :friends
      list :comments

      def foo
        bar.foo
      end

      def baz
        bar.new.foo
      end

      def bar
        SomeMissingConstant
      end
    end

    should "provide a meaningful inspect" do
      bar = Bar.new

      assert_equal "#<Bar:? name=nil friends=nil comments=nil visits=0>", bar.inspect

      bar.update(:name => "Albert")
      bar.friends << 1
      bar.friends << 2
      bar.comments << "A"
      bar.incr(:visits)

      assert_equal %Q{#<Bar:#{bar.id} name="Albert" friends=#<Set: ["1", "2"]> comments=#<List: ["A"]> visits=1>}, Bar[bar.id].inspect
    end

    def assert_wrapper_exception(&block)
      begin
        block.call
      rescue NoMethodError => exception_raised
      end

      assert_match /You tried to call SomeMissingConstant#\w+, but SomeMissingConstant is not defined on #{__FILE__}:\d+:in `bar'/, exception_raised.message
    end

    should "inform about a miscatch by Wrapper when calling class methods" do
      assert_wrapper_exception { Bar.new.baz }
    end

    should "inform about a miscatch by Wrapper when calling instance methods" do
      assert_wrapper_exception { Bar.new.foo }
    end
  end

  context "Overwriting write" do
    class ::Baz < Ohm::Model
      attribute :name

      def write
        self.name = "Foobar"
        super
      end
    end

    should "work properly" do
      baz = Baz.new
      baz.name = "Foo"
      baz.save
      baz.name = "Foo"
      baz.save
      assert_equal "Foobar", Baz[baz.id].name
    end
  end

  context "References to other objects" do
    class ::Note < Ohm::Model
      attribute :content
      reference :source, Post
      collection :comments, Comment
      list :ratings, Rating
    end

    class ::Comment < Ohm::Model
      reference :note, Note
    end

    class ::Rating < Ohm::Model
      attribute :value
    end

    class ::Editor < Ohm::Model
      attribute :name
      reference :post, Post
    end

    class ::Post < Ohm::Model
      reference :author, Person
      collection :notes, Note, :source
      collection :editors, Editor
    end

    setup do
      @post = Post.create
    end

    context "a reference to another object" do
      should "return an instance of Person if author_id has a valid id" do
        @post.author_id = Person.create(:name => "Albert").id
        @post.save
        assert_equal "Albert", Post[@post.id].author.name
      end

      should "assign author_id if author is sent a valid instance" do
        @post.author = Person.create(:name => "Albert")
        @post.save
        assert_equal "Albert", Post[@post.id].author.name
      end

      should "assign nil if nil is passed to author" do
        @post.author = nil
        @post.save
        assert_nil Post[@post.id].author
      end

      should "be cached in an instance variable" do
        @author = Person.create(:name => "Albert")
        @post.update(:author => @author)

        assert_equal @author, @post.author
        assert @post.author.object_id == @post.author.object_id

        @post.update(:author => Person.create(:name => "Bertrand"))

        assert_equal "Bertrand", @post.author.name
        assert @post.author.object_id == @post.author.object_id

        @post.update(:author_id => Person.create(:name => "Charles").id)

        assert_equal "Charles", @post.author.name
      end
    end

    context "a collection of other objects" do
      setup do
        @note = Note.create(:content => "Interesting stuff", :source => @post)
        @comment = Comment.create(:note => @note)
      end

      should "return a set of notes" do
        assert_equal @note.source, @post
        assert_equal @note, @post.notes.first
      end

      should "return a set of comments" do
        assert_equal @comment, @note.comments.first
      end

      should "return a list of ratings" do
        @rating = Rating.create(:value => 5)
        @note.ratings << @rating

        assert_equal @rating, @note.ratings.first
      end

      should "default to the current class name" do
        @editor = Editor.create(:name => "Albert", :post => @post)

        assert_equal @editor, @post.editors.first
      end
    end
  end

  context "Models connected to different databases" do
    class ::Car < Ohm::Model
      attribute :name
    end

    class ::Make < Ohm::Model
      attribute :name
    end

    setup do
      Car.connect(:port => 6379, :db => 14)
    end

    teardown do
      Car.db.flushdb
    end

    should "save to the selected database" do
      car = Car.create(:name => "Twingo")
      make = Make.create(:name => "Renault")

      assert_equal ["1"], Redis.new(:db => 15).smembers("Make:all")
      assert_equal [], Redis.new(:db => 15).smembers("Car:all")

      assert_equal ["1"], Redis.new(:db => 14).smembers("Car:all")
      assert_equal [], Redis.new(:db => 14).smembers("Make:all")

      assert_equal car, Car[1]
      assert_equal make, Make[1]

      Make.db.flushdb

      assert_equal car, Car[1]
      assert_nil Make[1]
    end

    should "allow changing the database" do
      Car.create(:name => "Twingo")

      assert_equal ["1"], Car.all.raw

      Car.connect :db => 15
      assert_equal [], Car.all.raw

      Car.connect :db => 14
      assert_equal ["1"], Car.all.raw
    end
  end

  context "Persistence" do
    should "persist attributes to a hash" do
      event = Event.create(:name => "Redis Meetup")
      event.incr(:votes)

      assert_equal "hash", Ohm.redis.type("Event:1")

      assert_equal [
        "Event:1", "Event:all", "Event:id"
      ].sort, Ohm.redis.keys("Event:*").sort

      assert_equal "Redis Meetup", Event[1].name
      assert_equal 1, Event[1].votes
    end
  end

  context "Exporting" do
    class Person < Ohm::Model
      attribute :name

      def validate
        assert_present :name
      end
    end

    context "a new model without errors" do
      should "export an empty hash via to_hash" do
        person = Person.new
        assert_equal({}, person.to_hash)
      end
    end

    context "a new model with some errors" do
      should "export a hash with the errors" do
        person = Person.new
        person.valid?

        assert_equal({ :errors => [[:name, :not_present]] }, person.to_hash)
      end
    end

    context "an existing model" do
      should "export a hash with the its id" do
        person = Person.create(:name => "John Doe")
        assert_equal({ :id => '1' }, person.to_hash)
      end
    end

    context "an existing model with validation errors" do
      should "export a hash with its id and the errors" do
        person = Person.create(:name => "John Doe")
        person.name = nil
        person.valid?

        expected_hash = { :id => '1', :errors => [[:name, :not_present]] }

        assert_equal expected_hash, person.to_hash
      end
    end

    class Programmer < Ohm::Model
      attribute :language

      def validate
        assert_present :language
      end

      def to_hash
        super.merge(:language => language)
      end
    end

    context "a subclassed to_hash" do
      should "return the merged attributes" do
        programmer = Programmer.create(:language => "Ruby")
        expected_hash = { :id => '1', :language => 'Ruby' }

        assert_equal expected_hash, programmer.to_hash
      end
    end

    context "the JSON representation of an object" do
      should "just be the to_hash of a model" do
        programmer = Programmer.create(:language => "Ruby")
        expected_json = %({"id":"1","language":"Ruby"})

        assert_equal expected_json, programmer.to_json
      end
    end
  end

  describe "a Model with individual attribute writing needs" do
    class Order < Ohm::Model
      attribute :state

      def authorize!
        write_remote :state, 'authorized'
      end
    end

    test "writes locally" do
      order = Order.create(:state => "pending")
      order.authorize!
      assert_equal 'authorized', order.state
    end

    test "writes remotely" do
      order = Order.create(:state => "pending")
      order.authorize!
      order = Order[order.id]
      assert_equal 'authorized', order.state
    end
  end
end
