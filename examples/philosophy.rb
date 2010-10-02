### Internals: Nest and the Ohm Philosophy

#### Ohm does not want to hide Redis from you

# In contrast to the usual philosophy of ORMs in the wild, Ohm actually
# just provides a basic object mapping where you can safely tuck away
# attributes and declare grouping of data.
#
# Beyond that, Ohm doesn't try to hide Redis, but rather exposes it in
# a simple way, through key hierarchies provided by the library
# [Nest](http://github.com/soveran/nest).

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

  list :comments, Comment

  # This is one example of using the underlying library `Nest` directly.
  # As you can see, we can easily drop down to using raw *Redis* commands,
  # in this case we use
  # [ZREVRANGE](http://code.google.com/p/redis/wiki/ZrangeCommand).
  #
  # *Note:* Since `Ohm::Model` defines a `to_proc`, we can use the `&` syntax
  # together with `map` to make our code a little more terse.
  def self.latest
    key[:latest].zrevrange(0, -1).map(&Post)
  end

  # Here we just quickly push this instance of `Post` to our `latest`
  # *SORTED SET*. We use the current time as the score.
protected
  def after_save
    self.class.key[:latest].zadd(Time.now.to_i, id)
  end

  # Since we add every `Post` to our *SORTED SET*, we have to make sure that
  # we removed it from our `latest` *SORTED SET* as soon as we delete a
  # `Post`.
  #
  # In this case we use the raw *Redis* command
  # [ZREM](http://code.google.com/p/redis/wiki/ZremCommand).
  def after_delete
    self.class.key[:latest].zrem(id)
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
prepare { Ohm.flush }

# Now let's create Post. `Cutest` by default yields the return value of the
# block to each and every one of the test blocks.
setup { Post.create }

# We then verify the behavior for our `Post:latest` ZSET. Our created
# post should automatically be part of `Post:latest`.
test "created post is inserted into latest" do |p|
  assert [p.id] == Post.key[:latest].zrange(0, -1)
end

# And it should automatically be removed from it as soon as we delete our
# `Post`.
test "deleting the created post removes it from latest" do |p|
  p.delete

  assert Post.key[:latest].zrange(0, -1).empty?
end

# You might be curious what happens when we do `Post.all`. The test here
# demonstrates more or less what's happening when you do that.
test "querying Post:all using raw Redis commands" do |p|
  assert [p.id] == Post.key[:all].smembers

  assert [p] == Post.key[:all].smembers.map(&Post)
end

#### Understanding `post.comments`.

# Let's pop the hood and see how we can do *LIST* operations on our
# `post.comments` object.

# Getting the current size of our comments is just a wrapper for
# [LLEN](http://code.google.com/p/redis/wiki/LlenCommand).
test "checking the number of comments for a given post" do |p|
  assert 0 == p.comments.key.llen
  assert 0 == p.comments.size
end

# Also, pushing a comment to our `post.comments` object is equivalent
# to doing an [RPUSH](http://code.google.com/p/redis/wiki/RpushCommand)
# of its `id`.
test "pushing a Comment manually and checking for its presence" do |p|
  comment = Comment.create

  p.comments.key.rpush(comment.id)
  assert [comment.id] == p.comments.key.lrange(0, -1)
end

# Now for some interesting judo
test "now what if we want to find all Ohm or Redis posts" do
  ohm = Post.create(:title => "Ohm")
  redis = Post.create(:title => "Redis")

  # Let's first choose an arbitrary key name to hold our `Set`.
  ohm_redis = Post.key.volatile["ohm-redis"]

  # A *volatile* key just simply means it will be prefixed with a `~`.
  assert "~:Post:ohm-redis" == ohm_redis

  # Finding all *Ohm* or *Redis* posts now will just be a call to
  # [SUNIONSTORE](http://code.google.com/p/redis/wiki/SunionstoreCommand)
  # on our *volatile* `ohm-redis` key.
  ohm_redis.sunionstore(
    Post.index_key_for(:title, "Ohm"),
    Post.index_key_for(:title, "Redis")
  )

  # And voila, they have been found!
  assert [ohm.id, redis.id] == ohm_redis.smembers.sort
end

#### The command reference is your friend

# If you invest a little time reading through all the different
# [Redis commands](http://code.google.com/p/redis/wiki/CommandReference),
# I'm pretty sure you will enjoy your experience hacking with Ohm, Nest and
# Redis a lot more.
