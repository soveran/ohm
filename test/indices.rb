# encoding: UTF-8

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

  def working_days
    @working_days ||= []
  end

  def email_provider
    email.split("@").last
  end

  def before_save
    self.activation_code ||= "user:#{id}"
  end
end

setup do
  @user1 = User.create(email: "foo", activation_code: "bar", update: "baz")
  @user2 = User.create(email: "bar")
  @user3 = User.create(email: "baz qux")
end

test "be able to find by the given attribute" do
  assert @user1 == User.find(email: "foo").first
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
  assert_equal "User:indices:email:foo", User.find(email: "foo").key
end

test "cleanup the temporary key after use" do
  assert User.find(:email => "foo", :activation_code => "bar").to_a

  assert Ohm.redis.keys("User:temp:*").empty?
end

test "allow multiple chained finds" do
  assert 1 == User.find(:email => "foo").find(:activation_code => "bar").find(:update => "baz").size
end

test "return nil if no results are found" do
  assert User.find(:email => "foobar").empty?
  assert nil == User.find(:email => "foobar").first
end

test "update indices when changing attribute values" do
  @user1.email = "baz"
  @user1.save

  assert [] == User.find(:email => "foo").to_a
  assert [@user1] == User.find(:email => "baz").to_a
end

test "remove from the index after deleting" do
  @user2.delete

  assert [] == User.find(:email => "bar").to_a
end

test "work with attributes that contain spaces" do
  assert [@user3] == User.find(:email => "baz qux").to_a
end

# Indexing arbitrary attributes
setup do
  @user1 = User.create(:email => "foo@gmail.com")
  @user2 = User.create(:email => "bar@gmail.com")
  @user3 = User.create(:email => "bazqux@yahoo.com")
end

test "allow indexing by an arbitrary attribute" do
  gmail = User.find(:email_provider => "gmail.com").to_a
  assert [@user1, @user2] == gmail.sort_by { |u| u.id }
  assert [@user3] == User.find(:email_provider => "yahoo.com").to_a
end
