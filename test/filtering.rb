require_relative "helper"

class User < Ohm::Model
  attribute :fname
  attribute :lname
  attribute :status

  index :fname
  index :lname
  index :status
end

setup do
  u1 = User.create(:fname => "John", :lname => "Doe", :status => "active")
  u2 = User.create(:fname => "Jane", :lname => "Doe", :status => "active")

  [u1, u2]
end

test "findability" do |john, jane|
  assert_equal 1, User.find(:lname => "Doe", :fname => "John").size
  assert User.find(:lname => "Doe", :fname => "John").include?(john)

  assert_equal 1, User.find(:lname => "Doe", :fname => "Jane").size
  assert User.find(:lname => "Doe", :fname => "Jane").include?(jane)
end

test "sets aren't mutable" do |john, jane|
  assert_raise NoMethodError do
    User.find(:lname => "Doe").add(john)
  end

  assert_raise NoMethodError do
    User.find(:lname => "Doe", :fname => "John").add(john)
  end
end

test "#first" do |john, jane|
  set = User.find(:lname => "Doe", :status => "active")

  assert_equal jane, set.first(:by => "fname", :order => "ALPHA")
  assert_equal john, set.first(:by => "fname", :order => "ALPHA DESC")

  assert_equal "Jane", set.first(:by => "fname", :order => "ALPHA", :get => "fname")
  assert_equal "John", set.first(:by => "fname", :order => "ALPHA DESC", :get => "fname")
end

test "#[]" do |john, jane|
  set = User.find(:lname => "Doe", :status => "active")

  assert_equal john, set[john.id]
  assert_equal jane, set[jane.id]
end

test "#except" do |john, jane|
  User.create(:status => "inactive", :lname => "Doe")

  res = User.find(:lname => "Doe").except(:status => "inactive")

  assert_equal 2, res.size
  assert res.include?(john)
  assert res.include?(jane)

  res = User.all.except(:status => "inactive")

  assert_equal 2, res.size
  assert res.include?(john)
  assert res.include?(jane)
end

test "#except unions keys when passing an array" do |john, jane|
  expected = User.create(:fname => "Jean", :status => "inactive")

  res = User.find(:status => "inactive").except(:fname => [john.fname, jane.fname])

  assert_equal 1, res.size
  assert res.include?(expected)

  res = User.all.except(:fname => [john.fname, jane.fname])

  assert_equal 1, res.size
  assert res.include?(expected)
end

test "indices bug related to a nil attribute" do |john, jane|
  # First we create a record with a nil attribute
  out = User.create(:status => nil, :lname => "Doe")

  # Then, we update the old nil attribute to a different
  # non-nil, value.
  out.update(status: "inactive")

  # At this point, the index for the nil attribute should
  # have been cleared.
  assert_equal 0, User.redis.call("SCARD", "User:indices:status:")
end

test "#union" do |john, jane|
  User.create(:status => "super", :lname => "Doe")
  included = User.create(:status => "inactive", :lname => "Doe")

  res = User.find(:status => "active").union(:status => "inactive")

  assert_equal 3, res.size
  assert res.include?(john)
  assert res.include?(jane)
  assert res.include?(included)

  res = User.find(:status => "active").union(:status => "inactive").find(:lname => "Doe")

  assert res.any? { |e| e.status == "inactive" }
end

test "#combine" do |john, jane|
  res = User.find(:status => "active").combine(fname: ["John", "Jane"])

  assert_equal 2, res.size
  assert res.include?(john)
  assert res.include?(jane)
end

# book author thing via @myobie
scope do
  class Book < Ohm::Model
    collection :authors, :Author
  end

  class Author < Ohm::Model
    reference :book, :Book

    attribute :mood
    index :mood
  end

  setup do
    book1 = Book.create
    book2 = Book.create

    Author.create(:book => book1, :mood => "happy")
    Author.create(:book => book1, :mood => "sad")
    Author.create(:book => book2, :mood => "sad")

    [book1, book2]
  end

  test "straight up intersection + union" do |book1, book2|
    result = book1.authors.find(:mood => "happy").
      union(:book_id => book1.id, :mood => "sad")

    assert_equal 2, result.size
  end

  test "appending an empty set via union" do |book1, book2|
    res = Author.find(:book_id => book1.id, :mood => "happy").
      union(:book_id => book2.id, :mood => "sad").
      union(:book_id => book2.id, :mood => "happy")

    assert_equal 2, res.size
  end

  test "revert by applying the original intersection" do |book1, book2|
    res = Author.find(:book_id => book1.id, :mood => "happy").
      union(:book_id => book2.id, :mood => "sad").
      find(:book_id => book1.id, :mood => "happy")

    assert_equal 1, res.size
  end

  test "remove original intersection by doing diff" do |book1, book2|
    res = Author.find(:book_id => book1.id, :mood => "happy").
      union(:book_id => book2.id, :mood => "sad").
      except(:book_id => book1.id, :mood => "happy")

    assert_equal 1, res.size
    assert res.map(&:mood).include?("sad")
    assert res.map(&:book_id).include?(book2.id)
  end

  test "@myobie usecase" do |book1, book2|
    res = book1.authors.find(:mood => "happy").
      union(:mood => "sad", :book_id => book1.id)

    assert_equal 2, res.size
  end
end
