### Building an activity feed

#### Common solutions using a relational design

# When faced with this application requirement, the most common approach by
# far have been to create an *activities* table, and rows in this table would
# reference a *user*. Activities would typically be generated for each
# follower (or friend) when a certain user performs an action, like posting a
# new status update.

#### Problems

# The biggest issue with this design, is that the *activities* table will
# quickly get very huge, at which point you would need to shard it on
# *user_id*. Also, inserting thousands of entries per second would quickly
# bring your database to its knees.

#### Ohm Solution

# As always we need to require `Ohm`.
require "ohm"

# We create a `User` class, with a `set` for all the other users he
# would be `following`, and another `set` for all his `followers`.
class User < Ohm::Model
  set :followers, User
  set :following, User

  # Because a `User` literally has a `list` of activities, using a Redis
  # `list` to model the activities would be a good choice. We default to
  # getting the first 100 activities, and use
  # [lrange](http://redis.io/commands/lrange) directly.
  def activities(start = 0, limit = 100)
    redis.call 'LRANGE', key[:activities], start, start + limit
  end

  # Broadcasting a message to all the `followers` of a user would simply
  # be prepending the message for each if his `followers`. We also use
  # the Redis command
  # [lpush](http://redis.io/commands/lpush) directly.
  def broadcast(str)
    followers.each do |user|
      redis.call 'LPUSH', user.key[:activities], str
    end
  end

  # Given that *Jane* wants to follow *John*, we simply do the following
  # steps:
  #
  # 1. *John* is added to *Jane*'s `following` list.
  # 2. *Jane* is added to *John*'s `followers` list.
  def follow(other)
    following << other
    other.followers << self
  end
end


#### Testing

# We'll use cutest for our testing framework.
require "cutest"

# The database is flushed before each test.
prepare { Ohm.flush }

# We define two users, `john` and `jane`, and yield them so all
# other tests are given access to these 2 users.
setup do
  john = User.create
  jane = User.create

  [john, jane]
end

# Let's verify our model for `follow`. When `jane` follows `john`,
# the following conditions should hold:
#
# 1. The followers list of `john` is comprised *only* of `jane`.
# 2. The list of users `jane` is following is comprised *only* of `john`.
test "jane following john" do |john, jane|
  jane.follow(john)

  assert_equal [john], jane.following.to_a
  assert_equal [jane], john.followers.to_a
end

# Broadcasting a message should simply notify all the followers of the
# `broadcaster`.
test "john broadcasting a message" do |john, jane|
  jane.follow(john)
  john.broadcast("Learning about Redis and Ohm")

  assert jane.activities.include?("Learning about Redis and Ohm")
end

#### Total Denormalization: Adding HTML

# This may be a real edge case design decision, but for some scenarios this
# may work. The beauty of this solution is that you only have to generate the
# output once, and successive refreshes of the end user will help you save
# some CPU cycles.
#
# This example of course assumes that the code that generates this does all
# the conditional checks (possibly changing the point of view like *Me:*
# instead of *John says:*).
test "broadcasting the html directly" do |john, jane|
  jane.follow(john)

  snippet = '<a href="/1">John</a> says: How\'s it going ' +
            '<a href="/user/2">jane</a>?'

  john.broadcast(snippet)

  assert jane.activities.include?(snippet)
end

#### Saving Space

# In most cases, users don't really care about keeping their entire activity
# history. This application requirement would be fairly trivial to implement.

# Let's reopen our `User` class and define a new broadcast method.
class User
  # We define a constant where we set the maximum number of activity entries.
  MAX = 10

  # Using `MAX` as the reference, we truncate the activities feed using
  # [ltrim](http://redis.io/commands/ltrim).
  def broadcast(str)
    followers.each do |user|
      redis.call 'LPUSH', user.key[:activities], str
      redis.call 'LTRIM', user.key[:activities], 0, MAX - 1
    end
  end
end

# Now let's verify that this new behavior is enforced.
test "pushing 11 activities maintains the list to 10" do |john, jane|
  jane.follow(john)

  11.times { john.broadcast("Flooding your feed!") }

  assert 10 == jane.activities.size
end


#### Conclusion

# As you can see, choosing a more straightforward approach (in this case,
# actually having a list per user, instead of maintaining a separate
# `activities` table) will greatly simplify the design of your system.
#
# As a final note, keep in mind that the Ohm solution would still need
# sharding for large datasets, but that would be again trivial to implement
# using [redis-rb](http://github.com/redis/redis-rb)'s distributed support
# and sharding it against the *user_id*.
