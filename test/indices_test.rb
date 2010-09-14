require File.expand_path("./helper", File.dirname(__FILE__))

class User < Ohm::Model
  attribute :email
  attribute :update
  attribute :activation_code
  attribute :sandunga

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

setup do
  Ohm.flush

  @user1 = User.create(:email => "foo", :activation_code => "bar", :update => "baz")
  @user2 = User.create(:email => "bar")
  @user3 = User.create(:email => "baz qux")
end

test "be able to find by the given attribute" do
  assert @user1 == User.find(:email => "foo").first
end

test "raise an error if the parameter supplied is not a hash" do
  begin
    User.find(1)
  rescue => ex
  ensure
    assert ex.kind_of?(ArgumentError)
    assert ex.message == "You need to supply a hash with filters. If you want to find by ID, use User[id] instead."
  end
end

test "avoid intersections with the all collection" do
  assert "User:email:#{Ohm::Model.encode "foo"}" == User.find(:email => "foo").key.to_s

  assert "~:User:email:Zm9v+User:activation_code:" ==
    User.find(:email => "foo").find(:activation_code => "").key.to_s

  assert "~:User:email:Zm9v+User:activation_code:YmFy+User:update:YmF6" ==
    result = User.find(:email => "foo").find(:activation_code => "bar").find(:update => "baz").key.to_s
end

test "use a special namespace for set operations" do
  assert User.find(:email => "foo", :activation_code => "bar").key.to_s.match(/^~:/)

  assert Ohm.redis.keys("~:*").size > 0
end

test "allow multiple chained finds" do
  assert 1 == User.find(:email => "foo").find(:activation_code => "bar").find(:update => "baz").size
end

test "raise if the field is not indexed" do
  assert_raise(Ohm::Model::IndexNotFound) do
    User.find(:sandunga => "foo")
  end
end

test "return nil if no results are found" do
  assert User.find(:email => "foobar").empty?
  assert nil == User.find(:email => "foobar").first
end

test "update indices when changing attribute values" do
  @user1.email = "baz"
  @user1.save

  assert [] == User.find(:email => "foo").all
  assert [@user1] == User.find(:email => "baz").all
end

test "remove from the index after deleting" do
  @user2.delete

  assert [] == User.find(:email => "bar").all
end

test "work with attributes that contain spaces" do
  assert [@user3] == User.find(:email => "baz qux").all
end

# Indexing arbitrary attributes
setup do
  Ohm.flush

  @user1 = User.create(:email => "foo@gmail.com")
  @user2 = User.create(:email => "bar@gmail.com")
  @user3 = User.create(:email => "bazqux@yahoo.com")
end

test "allow indexing by an arbitrary attribute" do
  assert [@user1, @user2] == User.find(:email_provider => "gmail.com").to_a.sort_by { |u| u.id }
  assert [@user3] == User.find(:email_provider => "yahoo.com").all
end

test "allow indexing by an attribute that is lazily set" do
  assert [@user1] == User.find(:activation_code => "user:1").to_a
end

# Indexing enumerables
setup do
  Ohm.flush

  @user1 = User.create(:email => "foo@gmail.com")
  @user2 = User.create(:email => "bar@gmail.com")

  @user1.working_days << "Mon"
  @user1.working_days << "Tue"
  @user2.working_days << "Mon"
  @user2.working_days << "Wed"

  @user1.save
  @user2.save
end

test "index each item" do
  assert [@user1, @user2] == User.find(:working_days => "Mon").to_a.sort_by { |u| u.id }
end

# TODO If we deal with Ohm collections, the updates are atomic but the reindexing never happens.
# One solution may be to reindex after inserts or deletes in collection.
test "remove the indices when the object changes" do
  @user2.working_days.delete "Mon"
  @user2.save
  assert [@user1] == User.find(:working_days => "Mon").all
end

# Intersection and difference
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
  Ohm.flush

  @event1 = Event.create(:timeline => 1).update(:days => [1, 2])
  @event2 = Event.create(:timeline => 1).update(:days => [2, 3])
  @event3 = Event.create(:timeline => 2).update(:days => [3, 4])
  @event4 = Event.create(:timeline => 2).update(:days => [1, 3])
end

test "intersect multiple sets of results" do
  assert [@event1] == Event.find(:days => [1, 2]).all
  assert [@event1] == Event.find(:timeline => 1, :days => [1, 2]).all
  assert [@event1] == Event.find(:timeline => 1).find(:days => [1, 2]).all
end

test "compute the difference between sets" do
  assert [@event2] == Event.find(:timeline => 1).except(:days => 1).all
end

test "raise if the argument is not an index" do
  assert_raise(Ohm::Model::IndexNotFound) do
    Event.find(:timeline => 1).except(:not_an_index => 1)
  end
end

test "work with strings that generate a new line when encoded" do
  user = User.create(:email => "foo@bar", :update => "CORRECTED - UPDATE 2-Suspected US missile strike kills 5 in Pakistan")
  assert [user] == User.find(:update => "CORRECTED - UPDATE 2-Suspected US missile strike kills 5 in Pakistan").all
end

# New indices
test "populate a new index when the model is saved" do
  class Event < Ohm::Model
    attribute :name
  end

  foo = Event.create(:name => "Foo")

  assert_raise(Ohm::Model::IndexNotFound) { Event.find(:name => "Foo") }

  class Event < Ohm::Model
    index :name
  end

  # Find works correctly once the index is added.
  Event.find(:name => "Foo")

  # The index was added after foo was created.
  assert Event.find(:name => "Foo").empty?

  bar = Event.create(:name => "Bar")

  # Bar was indexed properly.
  assert bar == Event.find(:name => "Bar").first

  # Saving all the objects populates the indices.
  Event.all.each { |e| e.save }

  # Now foo is indexed.
  assert foo == Event.find(:name => "Foo").first
end
