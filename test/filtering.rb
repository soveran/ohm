require File.expand_path("./helper", File.dirname(__FILE__))

class User < Ohm::Model
  attribute :fname
  attribute :lname
  attribute :status
  index :fname
  index :lname
  index :status
end

setup do
  u1 = User.create(fname: "John", lname: "Doe", status: "active")
  u2 = User.create(fname: "Jane", lname: "Doe", status: "active")

  [u1, u2]
end

test "findability" do |john, jane|
  assert_equal 1, User.find(lname: "Doe", fname: "John").size
  assert User.find(lname: "Doe", fname: "John").include?(john)

  assert_equal 1, User.find(lname: "Doe", fname: "Jane").size
  assert User.find(lname: "Doe", fname: "Jane").include?(jane)
end

test "#first" do |john, jane|
  set = User.find(lname: "Doe", status: "active")

  assert_equal jane, set.first(by: "fname", order: "ALPHA")
  assert_equal john, set.first(by: "fname", order: "ALPHA DESC")

  assert_equal "Jane", set.first(by: "fname", order: "ALPHA", get: "fname")
  assert_equal "John", set.first(by: "fname", order: "ALPHA DESC", get: "fname")
end

test "#[]" do |john, jane|
  set = User.find(lname: "Doe", status: "active")

  assert_equal john, set[john.id]
  assert_equal jane, set[jane.id]
end
