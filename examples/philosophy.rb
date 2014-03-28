### Internals: Nest and the Ohm Philosophy

#### Ohm does not want to hide Redis from you

# In contrast to the usual philosophy of ORMs in the wild, Ohm actually
# just provides a basic object mapping where you can safely tuck away
# attributes and declare grouping of data.
#
# Beyond that, Ohm doesn't try to hide Redis, but rather exposes it in
# a simple way, through key hierarchies provided by the library
# [Nido](http://github.com/soveran/nido).

# Let's require `Ohm`. We also require `Ohm::Contrib` so we can make
# use of its module `Ohm::Callbacks`.
require "ohm"
require "ohm/contrib"

# Let's quickly declare our `Post` model and include `Ohm::Callbacks`.
# We define an *attribute* `title` and also *index* it.
#
# In addition we specify our `Post` to have a list of *comments*.
class Post < Ohm::Model
  include Ohm::Callbacks

  attribute :title
  index :title

  list :comments, :Comment

  # This is one example of using Redic simple API and
  # the underlying library `Nido`.
  def self.latest
    fetch(redis.call("ZRANGE", key[:latest], 0, -1))
  end

  protected

  # Here we just quickly push this instance of `Post` to our `latest`
  # *SORTED SET*. We use the current time as the score.
  def after_save
    redis.call("ZADD", model.key[:latest], Time.now.to_i, id)
  end

  # Since we add every `Post` to our *SORTED SET*, we have to make sure that
  # we removed it from our `latest` *SORTED SET* as soon as we delete a
  # `Post`.
  def after_delete
    redis.call("ZREM", model.key[:latest], id)
  end
end

# Now let's quickly define our `Comment` model.
class Comment < Ohm::Model
end

#### Test it out

# For this example, we'll use [Cutest](http://github.com/djanowski/cutest)
# for our testing framework.
require "cutest"

# To make it simple, we also ensure that every test run has a clean
# *Redis* instance.
prepare do
  Ohm.flush
end

# Now let's create a post. `Cutest` by default yields the return value of the
# block to each and every one of the test blocks.
setup do
  Post.create
end

# We then verify the behavior for our `Post:latest` ZSET. Our created
# post should automatically be part of `Post:latest`.
test "created post is inserted into latest" do |post|
  assert [post.id] == Post.latest.map(&:id)
end

# And it should automatically be removed from it as soon as we delete our
# `Post`.
test "deleting the created post removes it from latest" do |post|
  post.delete

  assert Post.latest.empty?
end

# You might be curious what happens when we do `Post.all`. The test here
# demonstrates more or less what's happening when you do that.
test "querying Post:all using raw Redis commands" do |post|
  assert [post.id] == Post.all.ids
  assert [post] == Post.all.to_a
end

#### Understanding `post.comments`.

# Let's pop the hood and see how we can do *LIST* operations on our
# `post.comments` object.

# Getting the current size of our comments is just a wrapper for
# [LLEN](http://redis.io/commands/LLEN).
test "checking the number of comments for a given post" do |post|
  assert_equal 0, post.comments.size
  assert_equal 0, Post.redis.call("LLEN", post.comments.key)
end

# Also, pushing a comment to our `post.comments` object is equivalent
# to doing an [RPUSH](http://redis.io/commands/RPUSH) of its `id`.
test "pushing a comment manually and checking for its presence" do |post|
  comment = Comment.create

  Post.redis.call("RPUSH", post.comments.key, comment.id)
  assert_equal comment, post.comments.last

  post.comments.push(comment)
  assert_equal comment, post.comments.last
end

# Now for some interesting judo.
test "now what if we want to find all Ohm or Redis posts" do
  ohm = Post.create(title: "Ohm")
  redis = Post.create(title: "Redis")

  # Finding all *Ohm* or *Redis* posts now will just be a call to
  # [SUNIONSTORE](http://redis.io/commands/UNIONSTORE).
  result = Post.find(title: "Ohm").union(title: "Redis")

  # And voila, they have been found!
  assert_equal [ohm, redis], result.to_a
end

#### The command reference is your friend

# If you invest a little time reading through all the different
# [Redis commands](http://redis.io/commands).
# I'm pretty sure you will enjoy your experience hacking with Ohm, Nido,
# Redic and Redis a lot more.
