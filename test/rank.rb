require_relative "helper"

class User < Ohm::Model
  attribute :age

  rank :age
end

setup do
  john = User.create(:age => 10)
  jane = User.create(:age => 15)

  [john, jane]
end

test "findability" do |john, jane|
  assert_equal 0, User.all.rank(:age, 0, 3).count

  assert_equal 1, User.all.rank(:age, 9, 11).count
  assert User.all.rank(:age, 9, 11).include?(john)

  assert_equal 1, User.all.rank(:age, 14, 16).count
  assert User.all.rank(:age, 9, 11).include?(john)
end
