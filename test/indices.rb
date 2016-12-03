require_relative "helper"

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
  @user1 = User.create(:email => "foo", :activation_code => "bar", :update => "baz")
  @user2 = User.create(:email => "bar")
  @user3 = User.create(:email => "baz qux")
end

test "be able to find by the given attribute" do
  assert @user1 == User.find(:email => "foo").first
end

test "raise if the index doesn't exist" do
  assert_raise Ohm::IndexNotFound do
    User.find(:address => "foo")
  end
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
  assert_equal "User:indices:email:foo", User.find(:email => "foo").key.to_s
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

scope do
  # Just to give more context around this bug, basically it happens
  # when you define a virtual unique or index.
  #
  # Previously it was unable to cleanup the indices mainly because
  # it relied on the attributes being set.
  class Node < Ohm::Model
    index :available
    attribute :capacity

    unique :available

    def available
      capacity.to_i <= 90
    end
  end

  test "index bug" do
    n = Node.create
    n.update(capacity: 91)

    assert_equal 0, Node.find(available: true).size
  end

  test "uniques bug" do
    n = Node.create
    n.update(capacity: 91)

    assert_equal nil, Node.with(:available, true)
  end
  
  test "float to string" do
    u1 = User.create(:email => "foo", :update => 3.0)
    u2 = User.create(:email => "bar", :update => 3)
    
    assert User.find(:update => 3.0).include?(u1)
    assert User.find(:update => 3).include?(u2)
    
    assert !User.find(:update => 3.0).include?(u2)
    assert !User.find(:update => 3).include?(u1)
  end
end
