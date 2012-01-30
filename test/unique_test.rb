# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

class User < Ohm::Model
  attribute :email
  unique :email
end

setup do
  User.create(email: "a@a.com")
end

test do |u|
  assert_equal u, User.with(:email, "a@a.com")
end

test do
  assert_raise Ohm::Model::UniqueIndexViolation do
    User.create(email: "a@a.com")
  end
end

test do
  u = User.create(email: "b@b.com")
  u.email = "a@a.com"

  assert_raise Ohm::Model::UniqueIndexViolation do
    u.save
  end
end

test do
  u = User.create(email: "c@c.com")
  u.update(email: "d@d.com")

  assert_equal nil, User.with(:email, "c@c.com")
  assert_equal u, User.with(:email, "d@d.com")
end