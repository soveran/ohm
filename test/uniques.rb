# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

class User < Ohm::Model
  attribute :email
  unique :email
  unique :provider

  def self.[](id)
    super(id.to_i)
  end

  def provider
    email[/@(.*?).com/, 1] if email
  end
end

setup do
  User.create(:email => "a@a.com")
end

test "findability" do |u|
  assert_equal u, User.with(:email, "a@a.com")
end

test "raises when it already exists during create" do
  assert_raise Ohm::UniqueIndexViolation do
    User.create(:email => "a@a.com")
  end
end

test "raises when it already exists during save" do
  u = User.create(:email => "b@b.com")
  u.email = "a@a.com"

  assert_raise Ohm::UniqueIndexViolation do
    u.save
  end
end

test "doesn't raise when saving again and again" do |u|
  ex = nil

  begin
    User[u.id].save
  rescue Exception => e
    ex = e
  end

  assert_equal nil, ex
end

test "removes the previous index when changing" do
  u = User.create(:email => "c@c.com")
  u.update(:email => "d@d.com")

  assert_equal nil, User.with(:email, "c@c.com")
  assert_equal nil, User.key[:unique][:email].hget("c@c.com")
  assert_equal u, User.with(:email, "d@d.com")
end

test "removes the previous index when deleting" do |u|
  u.delete

  assert_equal nil, User.with(:email, "a@a.com")
  assert_equal nil, User.key[:unique][:email].hget("a@a.com")
end

test "unique virtual attribute" do
  u = User.create(:email => "foo@yahoo.com")

  assert_equal u, User.with(:provider, "yahoo")

  # Yahoo should be allowed because this user is the one reserved for it.
  u.update(:email => "bar@yahoo.com")

  # `a` is not allowed though.
  assert_raise Ohm::UniqueIndexViolation do
    u.update(:email => "bar@a.com")
  end

  # And so is yahoo if we try creating a different user.
  assert_raise Ohm::UniqueIndexViolation do
    User.create(:email => "baz@yahoo.com")
  end
end

test "nil attributes are ignored" do
  ex = nil

  begin
    User.create
    User.create
  rescue Exception => e
    ex = e
  end

  assert_equal nil, ex
end
