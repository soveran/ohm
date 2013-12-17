require_relative 'helper'

class User < Ohm::Model
end

test "returns an empty hash if model doesn't have set attributes" do
  assert_equal Hash.new, User.new.to_hash
end

test "returns a hash with its id if model is persisted" do
  user = User.create

  assert_equal Hash[id: user.id], user.to_hash
end

class Person < Ohm::Model
  attribute :name

  def to_hash
    super.merge(name: name)
  end
end

test "returns additional attributes if the method is overrided" do
  person   = Person.create(name: "John")
  expected = { id: person.id, name: person.name }

  assert_equal expected, person.to_hash
end
