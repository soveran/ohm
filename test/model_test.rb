# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

require "ostruct"

class Post < Ohm::Model
  attribute :body
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

module SomeNamespace
  class Foo < Ohm::Model
    attribute :name
  end
end

class Meetup < Ohm::Model
  attribute :name
  attribute :location

  def validate
    assert_present :name
  end
end

test "assign attributes from the hash" do
  event = Event.new(:name => "Ruby Tuesday")
  assert event.name == "Ruby Tuesday"
end

test "assign an ID and save the object" do
  event1 = Event.create(:name => "Ruby Tuesday")
  event2 = Event.create(:name => "Ruby Meetup")

  assert "1" == event1.id
  assert "2" == event2.id
end

test "return the unsaved object if validation fails" do
  assert Person.create(:name => nil).kind_of?(Person)
end

test "updates attributes" do
  event = Meetup.create(:name => "Ruby Tuesday")
  event.update(:name => "Ruby Meetup")
  assert "Ruby Meetup" == event.name
end

test "return false if the validation fails" do
  event = Meetup.create(:name => "Ruby Tuesday")
  assert !event.update(:name => nil)
end

test "save the attributes in UTF8" do
 event = Meetup.create(:name => "32° Kisei-sen")
 assert "32° Kisei-sen" == Meetup[event.id].name
end

test "delete the attribute if set to nil" do
  event = Meetup.create(:name => "Ruby Tuesday", :location => "Los Angeles")
  assert "Los Angeles" == Meetup[event.id].location
  assert event.update(:location => nil)
  assert nil == Meetup[event.id].location
end

test "delete the attribute if set to an empty string" do
  event = Meetup.create(:name => "Ruby Tuesday", :location => "Los Angeles")
  assert "Los Angeles" == Meetup[event.id].location
  assert event.update(:location => "")
  assert nil == Meetup[event.id].location
end

test "not raise if an attribute is redefined" do
  class RedefinedModel < Ohm::Model
    attribute :name

    silence_warnings do
      attribute :name
    end
  end
end

test "not raise if a counter is redefined" do
  class RedefinedModel < Ohm::Model
    counter :age

    silence_warnings do
      counter :age
    end
  end
end

test "not raise if a list is redefined" do
  class RedefinedModel < Ohm::Model
    list :todo, lambda { }

    silence_warnings do
      list :todo, lambda { }
    end
  end
end

test "not raise if a set is redefined" do
  class RedefinedModel < Ohm::Model
    set :friends, lambda { }

    silence_warnings do
      set :friends, lambda { }
    end
  end
end

test "not raise if a collection is redefined" do
  class RedefinedModel < Ohm::Model
    list :toys, lambda { }

    silence_warnings do
      set :toys, lambda { }
    end
  end
end

test "not raise if a index is redefined" do
  class RedefinedModel < Ohm::Model
    attribute :color
    index :color
    index :color
  end
end

test "allow arbitrary IDs" do
  Event.create(:id => "abc123", :name => "Concert")

  assert Event.all.size == 1
  assert Event["abc123"].name == "Concert"
end

test "forbid assignment of IDs on a new object" do
  event = Event.new(:name => "Concert")

  assert_raise(NoMethodError) do
    event.id = "abc123"
  end
end

setup do
  Ohm.redis.sadd("Event:all", 1)
  Ohm.redis.hset("Event:1", "name", "Concert")
end

test "return an instance of Event" do
  assert Event[1].kind_of?(Event)
  assert 1 == Event[1].id
  assert "Concert" == Event[1].name
end

setup do
  Ohm.redis.sadd("User:all", 1)
  Ohm.redis.hset("User:1", "email", "albert@example.com")
end

test "return an instance of User" do
  assert User[1].kind_of?(User)
  assert 1 == User[1].id
  assert "albert@example.com" == User[1].email
end

test "allow to map key to models" do
  assert [User[1]] == [1].map(&User)
end

setup do
  Ohm.redis.sadd("User:all", 1)
  Ohm.redis.set("User:1:email", "albert@example.com")

  @user = User[1]
end

test "change its attributes" do
  @user.email = "maria@example.com"
  assert "maria@example.com" == @user.email
end

test "save the new values" do
  @user.email = "maria@example.com"
  @user.save

  @user.email = "maria@example.com"
  @user.save

  assert "maria@example.com" == User[1].email
end

test "assign a new id to the event" do
  event1 = Event.new
  event1.create

  event2 = Event.new
  event2.create

  assert !event1.new?
  assert !event2.new?

  assert "1" == event1.id
  assert "2" == event2.id
end

# Saving a model
test "create the model if it is new" do
  event = Event.new(:name => "Foo").save
  assert "Foo" == Event[event.id].name
end

test "save it only if it was previously created" do
  event = Event.new
  event.name = "Lorem ipsum"
  event.create

  event.name = "Lorem"
  event.save

  assert "Lorem" == Event[event.id].name
end

test "allow to hook into write" do
  event = Event.create(:name => "Foo")

  assert "foo" == event.slug
end

test "save counters" do
  event = Event.create(:name => "Foo")

  event.incr(:votes)
  event.save

  assert 1 == Event[event.id].votes
end

# Delete
test "delete an existing model" do
  class ModelToBeDeleted < Ohm::Model
    attribute :name
    set :foos, Post
    list :bars, Post
  end

  @model = ModelToBeDeleted.create(:name => "Lorem")

  @model.foos << Post.create
  @model.bars << Post.create

  id = @model.id

  @model.delete

  assert Ohm.redis.get(ModelToBeDeleted.key[id]).nil?
  assert Ohm.redis.get(ModelToBeDeleted.key[id][:name]).nil?
  assert Array.new == Ohm.redis.smembers(ModelToBeDeleted.key[id][:foos])
  assert Array.new == Ohm.redis.lrange(ModelToBeDeleted.key[id][:bars], 0, -1)

  assert ModelToBeDeleted.all.empty?
end

setup do
end

test "be no leftover keys" do
  class ::Foo < Ohm::Model
    attribute :name
    index :name
  end

  assert [] == Ohm.redis.keys("*")

  Foo.create(:name => "Bar")

  assert ["Foo:1:_indices", "Foo:1", "Foo:all", "Foo:id", "Foo:name:QmFy"].sort == Ohm.redis.keys("*").sort

  Foo[1].delete

  assert ["Foo:id"] == Ohm.redis.keys("*")
end

# Listing
test "find all" do
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

# Sorting
test "sort all" do
  Person.create :name => "D"
  Person.create :name => "C"
  Person.create :name => "B"
  Person.create :name => "A"

  assert %w[D C B A] == Person.all.sort_by(:id).map { |person| person.name }
  assert %w[A B C D] == Person.all.sort_by(:name, :order => "ALPHA").map { |person| person.name }
end

test "return an empty array if there are no elements to sort" do
  assert [] == Person.all.sort_by(:name)
end

test "return the first element sorted by id when using first" do
  Person.create :name => "A"
  Person.create :name => "B"
  assert "A" == Person.all.first.name
end

test "return the first element sorted by name if first receives a sorting option" do
  Person.create :name => "B"
  Person.create :name => "A"
  assert "A" == Person.all.first(:by => :name, :order => "ALPHA").name
end

test "return attribute values when the get parameter is specified" do
  Person.create :name => "B"
  Person.create :name => "A"

  assert "A" == Person.all.sort_by(:name, :get => :name, :order => "ALPHA").first
end

test "work on lists" do
  @post = Post.create :body => "Hello world!"
  @post.related << Post.create(:body => "C")
  @post.related << Post.create(:body => "B")
  @post.related << Post.create(:body => "A")

  assert ["A", "B", "C"] == @post.related.sort_by(:body, :order => "ALPHA ASC").map { |model| model.body }
end

# Loading attributes
setup do
  event = Event.new
  event.name = "Ruby Tuesday"
  @id = event.create.id
end

def monitor
  log = []

  monitor = Thread.new do
    Redis.connect.monitor do |line|
      break if line =~ /ping/
      log << line
    end
  end

  sleep 0.01

  log.clear.tap do
    yield
    Ohm.redis.ping
    monitor.join
  end
end

test "load attributes lazily" do
  event = Event[@id]

  log = monitor { event.name }

  assert !log.empty?

  log = monitor { event.name }

  assert log.empty?
end

test "load attributes as a strings" do
  event = Event.create(:name => 1)

  assert "1" == Event[event.id].name
end

# Attributes of type Set
setup do
  @person1 = Person.create(:name => "Albert")
  @person2 = Person.create(:name => "Bertrand")
  @person3 = Person.create(:name => "Charles")

  @event = Event.new
  @event.name = "Ruby Tuesday"
end

test "not be available if the model is new" do
  assert_raise Ohm::Model::MissingID do
    @event.attendees << Person.new
  end
end

test "remove an element if sent delete" do
  @event.create
  @event.attendees << @person1
  @event.attendees << @person2
  @event.attendees << @person3
  assert ["1", "2", "3"] == @event.attendees.key.sort
  @event.attendees.delete(@person2)
  assert ["1", "3"] == Event[@event.id].attendees.key.sort
end

test "return true if the set includes some member" do
  @event.create
  @event.attendees << @person1
  @event.attendees << @person2
  assert @event.attendees.include?(@person2)
  assert !@event.attendees.include?(@person3)
end

test "return instances of the passed model" do
  @event.create
  @event.attendees << @person1

  assert [@person1] == @event.attendees.all
  assert @person1 == @event.attendees[@person1.id]
end

test "return the size of the set" do
  @event.create
  @event.attendees << @person1
  @event.attendees << @person2
  @event.attendees << @person3
  assert 3 == @event.attendees.size
end

test "empty the set" do
  @event.create
  @event.attendees << @person1

  @event.attendees.clear

  assert @event.attendees.empty?
end

test "replace the values in the set" do
  @event.create
  @event.attendees << @person1

  assert [@person1] == @event.attendees.all

  @event.attendees.replace([@person2, @person3])

  assert [@person2, @person3] == @event.attendees.all.sort_by(&:id)
end

test "filter elements" do
  @event.create
  @event.attendees.add(@person1)
  @event.attendees.add(@person2)

  assert [@person1] == @event.attendees.find(:initial => "A").all
  assert [@person2] == @event.attendees.find(:initial => "B").all
  assert [] == @event.attendees.find(:initial => "Z").all
end

# Attributes of type List
setup do
  @post = Post.new
  @post.body = "Hello world!"
  @post.create
end

test "return an array" do
  assert @post.related.all.kind_of?(Array)
end

test "append elements with push" do
  @post.related.push Post.create
  @post.related << Post.create

  assert ["2", "3"] == @post.related.all.map { |model| model.id }
end

test "keep the inserting order" do
  @post.related << Post.create
  @post.related << Post.create
  @post.related << Post.create
  assert ["2", "3", "4"] == @post.related.all.map { |model| model.id }
end

test "keep the inserting order after saving" do
  @post.related << Post.create
  @post.related << Post.create
  @post.related << Post.create
  @post.save
  assert ["2", "3", "4"] == Post[@post.id].related.map { |model| model.id }
end

test "allow slicing the list" do
  post1 = Post.create
  post2 = Post.create
  post3 = Post.create

  @post.related << post1
  @post.related << post2
  @post.related << post3

  assert post1 == @post.related[0]
  assert post2 == @post.related[1]
  assert post3 == @post.related[-1]

  assert nil == @post.related[3]

  assert [post2, post3] == @post.related[1, 2]
  assert [post2, post3] == @post.related[1, -1]

  assert [] == @post.related[4, 5]

  assert [post2, post3] == @post.related[1..2]
  assert [post2, post3] == @post.related[1..5]

  assert [] == @post.related[4..5]
end

test "respond to each" do
  @post.related << Post.create
  @post.related << Post.create
  @post.related << Post.create

  i = 2
  @post.related.each do |c|
    assert i == c.id.to_i
    i += 1
  end
end

test "return the size of the list" do
  @post.related << Post.create
  @post.related << Post.create
  @post.related << Post.create
  assert 3 == @post.related.size
end

test "return the last element with pop" do
  @post.related << Post.create
  @post.related << Post.create
  assert "3" == @post.related.pop.id
  assert "2" == @post.related.pop.id
  assert @post.related.empty?
end

test "return the first element with shift" do
  @post.related << Post.create
  @post.related << Post.create
  assert "2" == @post.related.shift.id
  assert "3" == @post.related.shift.id
  assert @post.related.empty?
end

test "push to the head of the list with unshift" do
  @post.related.unshift Post.create
  @post.related.unshift Post.create
  assert "2" == @post.related.pop.id
  assert "3" == @post.related.pop.id
  assert @post.related.empty?
end

test "empty the list" do
  @post.related.unshift Post.create
  @post.related.clear

  assert @post.related.empty?
end

test "replace the values in the list" do
  @post.related.replace([Post.create, Post.create])

  assert ["2", "3"] == @post.related.map { |model| model.id }
end

test "add models" do
  @post.related.add(Post.create(:body => "Hello"))
  assert ["2"] == @post.related.map { |model| model.id }
end

test "find elements in the list" do
  another_post = Post.create

  @post.related.add(another_post)

  assert  @post.related.include?(another_post)
  assert !@post.related.include?(Post.create)
end

test "unshift models" do
  @post.related.unshift(Post.create(:body => "Hello"))
  @post.related.unshift(Post.create(:body => "Goodbye"))

  assert ["3", "2"] == @post.related.map { |model| model.id }

  assert "3" == @post.related.shift.id

  assert "2" == @post.related.pop.id

  assert @post.related.pop.nil?
end

# Applying arbitrary transformations
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

  @calendar.holidays.key.rpush "2009-05-25"
  @calendar.holidays.key.rpush "2009-07-09"

  @calendar.subscribers << MyActiveRecordModel.find(1)
end

test "apply a transformation" do
  assert [Date.new(2009, 5, 25), Date.new(2009, 7, 9)] == @calendar.holidays.all

  assert [1] == @calendar.subscribers.all.map { |model| model.id }
  assert [MyActiveRecordModel.find(1)] == @calendar.subscribers.all
end

test "allow lambdas in references" do
  appointment = Appointment.create(:subscriber => MyActiveRecordModel.find(1))
  assert MyActiveRecordModel.find(1) == appointment.subscriber
end

test "work with models too" do
  @calendar.appointments.add(Appointment.create(:text => "Meet with Bertrand"))

  assert [Appointment[1]] == Calendar[1].appointments.sort
end

# Sorting lists and sets
setup do
  @post = Post.create(:body => "Lorem")
  @post.related << Post.create
  @post.related << Post.create
  @post.related << Post.create
end

test "sort values" do
  assert %w{2 3 4} == @post.related.sort.map { |model| model.id }
end

# Sorting lists and sets by model attributes
setup do
  @event = Event.create(:name => "Ruby Tuesday")
  @event.attendees << Person.create(:name => "D")
  @event.attendees << Person.create(:name => "C")
  @event.attendees << Person.create(:name => "B")
  @event.attendees << Person.create(:name => "A")
end

test "sort the model instances by the values provided" do
  people = @event.attendees.sort_by(:name, :order => "ALPHA")
  assert %w[A B C D] == people.map { |person| person.name }
end

test "accept a number in the limit parameter" do
  people = @event.attendees.sort_by(:name, :limit => 2, :order => "ALPHA")
  assert %w[A B] == people.map { |person| person.name }
end

test "use the start parameter as an offset if the limit is provided" do
  people = @event.attendees.sort_by(:name, :limit => 2, :start => 1, :order => "ALPHA")
  assert %w[B C] == people.map { |person| person.name }
end

# Collections initialized with a Model parameter
setup do
  @user = User.create(:email => "albert@example.com")
  @user.posts.add Post.create(:body => "D")
  @user.posts.add Post.create(:body => "C")
  @user.posts.add Post.create(:body => "B")
  @user.posts.add Post.create(:body => "A")
end

test "return instances of the passed model" do
  assert Post == @user.posts.first.class
end

# Counters
setup do
  @event = Event.create(:name => "Ruby Tuesday")
end

test "raise ArgumentError if the attribute is not a counter" do
  assert_raise ArgumentError do
    @event.incr(:name)
  end
end

test "be zero if not initialized" do
  assert 0 == @event.votes
end

test "be able to increment a counter" do
  @event.incr(:votes)
  assert 1 == @event.votes

  @event.incr(:votes, 2)
  assert 3 == @event.votes
end

test "be able to decrement a counter" do
  @event.decr(:votes)
  assert @event.votes == -1

  @event.decr(:votes, 2)
  assert @event.votes == -3
end

# Comparison
setup do
  @user = User.create(:email => "foo")
end

test "be comparable to other instances" do
  assert @user == User[@user.id]

  assert @user != User.create
  assert User.new != User.new
end

test "not be comparable to instances of other models" do
  assert @user != Event.create(:name => "Ruby Tuesday")
end

test "be comparable to non-models" do
  assert @user != 1
  assert @user != true

  # Not equal although the other object responds to #key.
  assert @user != OpenStruct.new(:key => @user.send(:key))
end

# Debugging
class ::Bar < Ohm::Model
  attribute :name
  counter :visits
  set :friends, self
  list :comments, self

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

test "provide a meaningful inspect" do
  bar = Bar.new

  assert "#<Bar:? name=nil friends=nil comments=nil visits=0>" == bar.inspect

  bar.update(:name => "Albert")
  bar.friends << Bar.create
  bar.comments << Bar.create
  bar.incr(:visits)

  assert %Q{#<Bar:#{bar.id} name="Albert" friends=#<Set (Bar): ["2"]> comments=#<List (Bar): ["3"]> visits=1>} == Bar[bar.id].inspect
end

def assert_wrapper_exception(&block)
  begin
    block.call
  rescue NoMethodError => exception_raised
  end

  assert exception_raised.message =~
  /You tried to call SomeMissingConstant#\w+, but SomeMissingConstant is not defined on #{__FILE__}:\d+:in `bar'/
end

test "inform about a miscatch by Wrapper when calling class methods" do
  assert_wrapper_exception { Bar.new.baz }
end

test "inform about a miscatch by Wrapper when calling instance methods" do
  assert_wrapper_exception { Bar.new.foo }
end

# Overwriting write
class ::Baz < Ohm::Model
  attribute :name

  def write
    self.name = "Foobar"
    super
  end
end

test "work properly" do
  baz = Baz.new
  baz.name = "Foo"
  baz.save
  baz.name = "Foo"
  baz.save
  assert "Foobar" == Baz[baz.id].name
end

# Models connected to different databases
class ::Car < Ohm::Model
  attribute :name
end

class ::Make < Ohm::Model
  attribute :name
end

setup do
  Car.connect(:db => 15)
  Car.db.flushdb
end

test "save to the selected database" do
  car = Car.create(:name => "Twingo")
  make = Make.create(:name => "Renault")

  assert ["1"] == Redis.connect.smembers("Make:all")
  assert [] == Redis.connect.smembers("Car:all")

  assert ["1"] == Car.db.smembers("Car:all")
  assert [] == Car.db.smembers("Make:all")

  assert car == Car[1]
  assert make == Make[1]

  Make.db.flushdb

  assert car == Car[1]
  assert Make[1].nil?
end

test "allow changing the database" do
  Car.create(:name => "Twingo")

  assert ["1"] == Car.all.key.smembers

  Car.connect
  assert [] == Car.all.key.smembers

  Car.connect :db => 15
  assert ["1"] == Car.all.key.smembers
end

# Persistence
test "persist attributes to a hash" do
  event = Event.create(:name => "Redis Meetup")
  event.incr(:votes)

  assert "hash" == Ohm.redis.type("Event:1")

  assert [
    "Event:1", "Event:all", "Event:id"
  ].sort == Ohm.redis.keys("Event:*").sort

  assert "Redis Meetup" == Event[1].name
  assert 1 == Event[1].votes
end

# a Model with individual attribute writing needs
class Order < Ohm::Model
  attribute :state

  def authorize!
    write_remote :state, 'authorized'
  end
end

test "writes locally" do
  order = Order.create(:state => "pending")
  order.authorize!
  assert 'authorized' == order.state
end

test "writes remotely" do
  order = Order.create(:state => "pending")
  order.authorize!
  order = Order[order.id]
  assert 'authorized' == order.state
end

# namespaced models
test "be persisted" do
  SomeNamespace::Foo.create(:name => "foo")

  assert "hash" == Ohm.redis.type("SomeNamespace::Foo:1")

  assert "foo" == SomeNamespace::Foo[1].name
end
