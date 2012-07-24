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
  assert res.include?(jane)
end

test "indices bug related to a nil attribute" do |john, jane|
  # First we create a record with a nil attribute
  out = User.create(:status => nil, :lname => "Doe")

  # Then, we update the old nil attribute to a different
  # non-nil, value.
  out.update(status: "inactive")

  # At this point, the index for the nil attribute should
  # have been cleared.
  assert_equal 0, User.db.scard("User:indices:status:")
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

# test precision of filtering commands
require "logger"
require "stringio"
scope do
  class Post < Ohm::Model
    attribute :author
    index :author

    attribute :mood
    index :mood
  end

  setup do
    io = StringIO.new

    Post.connect(:logger => Logger.new(io))

    Post.create(author: "matz", mood: "happy")
    Post.create(author: "rich", mood: "mad")

    io
  end

  def read(io)
    io.rewind
    io.read
  end

  test "SINTERSTORE a b" do |io|
    Post.find(author: "matz").find(mood: "happy").to_a

    # This is the simple case. We should only do one SINTERSTORE
    # given two direct keys. Anything more and we're performing badly.
    expected = "SINTERSTORE Post:tmp:[a-f0-9]{64} " +
               "Post:indices:author:matz Post:indices:mood:happy"

    assert(read(io) =~ Regexp.new(expected))
  end

  test "SUNIONSTORE a b" do |io|
    Post.find(author: "matz").union(mood: "happy").to_a

    # Another simple case where we must only do one operation at maximum.
    expected = "SUNIONSTORE Post:tmp:[a-f0-9]{64} " +
               "Post:indices:author:matz Post:indices:mood:happy"

    assert(read(io) =~ Regexp.new(expected))
  end

  test "SUNIONSTORE c (SINTERSTORE a b)" do |io|
    Post.find(author: "matz").find(mood: "happy").union(author: "rich").to_a

    # For this case we need an intermediate key. This will
    # contain the intersection of matz + happy.
    expected = "SINTERSTORE (Post:tmp:[a-f0-9]{64}) " +
               "Post:indices:author:matz Post:indices:mood:happy"

    assert(read(io) =~ Regexp.new(expected))

    # The next operation is simply doing a UNION of the previously
    # generated intermediate key and the additional single key.
    expected = "SUNIONSTORE (Post:tmp:[a-f0-9]{64}) " +
               "%s Post:indices:author:rich" % $1

    assert(read(io) =~ Regexp.new(expected))
  end

  test "SUNIONSTORE (SINTERSTORE c d) (SINTERSTORE a b)" do |io|
    Post.find(author: "matz").find(mood: "happy").
         union(author: "rich", mood: "sad").to_a

    # Similar to the previous case, we need to do an intermediate
    # operation.
    expected = "SINTERSTORE (Post:tmp:[a-f0-9]{64}) " +
               "Post:indices:author:matz Post:indices:mood:happy"

    match1 = read(io).match(Regexp.new(expected))
    assert match1

    # But now, we need to also hold another intermediate key for the
    # condition of author: rich AND mood: sad.
    expected = "SINTERSTORE (Post:tmp:[a-f0-9]{64}) " +
               "Post:indices:author:rich Post:indices:mood:sad"

    match2 = read(io).match(Regexp.new(expected))
    assert match2

    # Now we expect that it does a UNION of those two previous
    # intermediate keys.
    expected = sprintf(
      "SUNIONSTORE (Post:tmp:[a-f0-9]{64}) %s %s",
      match1[1], match2[1]
    )

    assert(read(io) =~ Regexp.new(expected))
  end

  test do |io|
    Post.create(author: "kent", mood: "sad")

    Post.find(author: "kent", mood: "sad").
         union(author: "matz", mood: "happy").
         except(mood: "sad", author: "rich").to_a

    expected = "SINTERSTORE (Post:tmp:[a-f0-9]{64}) " +
               "Post:indices:author:kent Post:indices:mood:sad"

    match1 = read(io).match(Regexp.new(expected))
    assert match1

    expected = "SINTERSTORE (Post:tmp:[a-f0-9]{64}) " +
               "Post:indices:author:matz Post:indices:mood:happy"

    match2 = read(io).match(Regexp.new(expected))
    assert match2

    expected = sprintf(
      "SUNIONSTORE (Post:tmp:[a-f0-9]{64}) %s %s",
      match1[1], match2[1]
    )

    match3 = read(io).match(Regexp.new(expected))
    assert match3

    expected = "SINTERSTORE (Post:tmp:[a-f0-9]{64}) " +
               "Post:indices:mood:sad Post:indices:author:rich"

    match4 = read(io).match(Regexp.new(expected))
    assert match4

    expected = sprintf(
      "SDIFFSTORE (Post:tmp:[a-f0-9]{64}) %s %s",
      match3[1], match4[1]
    )

    assert(read(io) =~ Regexp.new(expected))
  end
end
