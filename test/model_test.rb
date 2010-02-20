# encoding: UTF-8

require File.join(File.dirname(__FILE__), "test_helper")
require "ostruct"

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

class TestRedis < Test::Unit::TestCase
  context "An event initialized with a hash of attributes" do
    should "assign the passed attributes" do
      event = Event.new(:name => "Ruby Tuesday")
      assert_equal event.name, "Ruby Tuesday"
    end
  end

  context "An event created from a hash of attributes" do
    should "assign an id and save the object" do
      Ohm.flush

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
      Ohm.flush

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

    should "return attribute values when the get parameter is specified" do
      Ohm.flush
      Person.create :name => "B"
      Person.create :name => "A"

      assert_equal "A", Person.all.sort_by(:name, :get => "Person:*:name", :order => "ALPHA").first
    end
  end

  context "Loading attributes" do
    setup do
      Ohm.flush

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
      assert_raise Ohm::Model::MissingID do
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

    should "empty the set" do
      @event.create
      @event.attendees << "1"

      @event.attendees.clear

      assert @event.attendees.empty?
    end

    should "replace the values in the set" do
      @event.create
      @event.attendees << "1"

      @event.attendees.replace(["2", "3"])

      assert_equal ["2", "3"], @event.attendees.raw.sort
    end

    should "filter elements" do
      @event.create
      @event.attendees.add(Person.create(:name => "Albert"))
      @event.attendees.add(Person.create(:name => "Marie"))

      assert_equal ["1"], @event.attendees.find(:initial => "A").raw
      assert_equal ["2"], @event.attendees.find(:initial => "M").raw
      assert_equal [],    @event.attendees.find(:initial => "Z").raw
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

      assert_equal ["1", "2"], @post.comments.raw
    end

    should "add models" do
      @post.related.add(Post.create(:body => "Hello"))

      assert_equal ["2"], @post.related.raw
    end

    should "find elements in the list" do
      another_post = Post.create

      @post.related.add(another_post)

      assert  @post.related.include?(another_post.id)
      assert !@post.related.include?("-1")
    end
  end

  context "Applying arbitrary transformations" do
    require "date"

    class Calendar < Ohm::Model
      list :holidays, lambda { |v| Date.parse(v) }
    end

    setup do
      @calendar = Calendar.create
      @calendar.holidays << "2009-05-25"
      @calendar.holidays << "2009-07-09"
    end

    should "apply a transformation" do
      assert_equal [Date.new(2009, 5, 25), Date.new(2009, 7, 9)], @calendar.holidays
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
  end

  context "Overwritting write" do
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
      reference :post => Post
    end

    class ::Post < Ohm::Model
      reference :author => Person
      collection :notes => [Note, :post_id]
    end

    setup do
      @post = Post.create
    end

    context "a reference to another object" do
      should "return an instance of Person if author_id has a valid id" do
        @post.author_id = Person.create(:name => "Michel").id
        @post.save
        assert_equal "Michel", Post[@post.id].author.name
      end

      should "assign author_id if author is sent a valid instance" do
        @post.author = Person.create(:name => "Michel")
        @post.save
        assert_equal "Michel", Post[@post.id].author.name
      end

      should "assign nil if nil is passed to author" do
        @post.author = nil
        @post.save
        assert_nil Post[@post.id].author
      end
    end

    context "a collection of other objects" do
      setup do
        @note = Note.create(:content => "Interesting stuff", :post => @post)
      end

      should "return a set of notes" do
        assert_equal @note.post, @post
        assert_equal @note, @post.notes.first
      end
    end
  end
end
