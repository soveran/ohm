### One to Many Ohm style

#### Problem

# Let's say you want to implement a commenting system, and you need to have
# comments on different models. In order to do this using an RDBMS you have
# one of two options:
#
# 1. Have multiple comment tables per type i.e. VideoComments, AudioComments,
#    etc.
# 2. Use a polymorphic schema.
#
# The problem with option 1 is that you'll may possibly run into an explosion
# of tables.
#
# The problem with option 2 is that if you have many comments across the whole
# site, you'll quickly hit the limit on a table, and eventually need to shard.

#### Solution

# In *Redis*, possibly the best data structure to model a comment would be to
# use a *List*, mainly because comments are always presented within the
# context of the parent entity, and are typically ordered in a predefined way
# (i.e. latest at the top, or latest at the bottom).
#

# Let's start by requiring `Ohm`.
require "ohm"

# We define both a `Video` and `Audio` model, with a `list` of *comments*.
class Video < Ohm::Model
  list :comments, :Comment
end

class Audio < Ohm::Model
  list :comments, :Comment
end

# The `Comment` model for this example will just contain one attribute called
# `body`.
class Comment < Ohm::Model
  attribute :body
end

# Now let's require the test framework we're going to use called
# [cutest](http://github.com/djanowski/cutest)
require "cutest"

# And make sure that every run of our test suite has a clean Redis instance.
prepare { Ohm.flush }

# Let's begin testing. The important thing to verify is that
# video comments and audio comments don't munge with each other.
#
# We can see that they don't since each of the `comments` list only has
# one element.
test "adding all sorts of comments" do
  video = Video.create

  video_comment = Comment.create(:body => "First Video Comment")
  video.comments.push(video_comment)

  audio = Audio.create
  audio_comment = Comment.create(:body => "First Audio Comment")
  audio.comments.push(audio_comment)

  assert video.comments.include?(video_comment)
  assert_equal video.comments.size, 1

  assert audio.comments.include?(audio_comment)
  assert_equal audio.comments.size, 1
end


#### Discussion
#
# As you can see above, the design is very simple, and leaves little to be
# desired.

# Latest first ordering can simply be achieved by using `unshift` instead of
# `push`.
test "latest first ordering" do
  video = Video.create

  first = Comment.create(:body => "First")
  second = Comment.create(:body => "Second")

  video.comments.unshift(first)
  video.comments.unshift(second)

  assert [second, first] == video.comments.to_a
end

# In addition, since Lists are optimized for doing `LRANGE` operations,
# pagination of Comments would be very fast compared to doing a LIMIT / OFFSET
# query in SQL (some sites also use `WHERE id > ? LIMIT N` and pass the
# previous last ID in the set).
test "getting paged chunks of comments" do
  video = Video.create

  20.times { |i| video.comments.push(Comment.create(:body => "C#{i + 1}")) }

  assert_equal %w(C1 C2 C3 C4 C5),  video.comments.range(0, 4).map(&:body)
  assert_equal %w(C6 C7 C8 C9 C10), video.comments.range(5, 9).map(&:body)
end

#### Caveats

# Sometimes you need to be able to delete comments. For these cases, you might
# possibly need to store a reference back to the parent entity. Also, if you
# expect to store millions of comments for a single entity, it might be tricky
# to delete comments, as you need to manually loop through the entire LIST.
#
# Luckily, there is a clean alternative solution, which would be to use a
# `SORTED SET`, and to use the timestamp (or the negative of the timestamp) as
# the score to maintain the desired order. Deleting a comment from a
# `SORTED SET` would be a simple
# [ZREM](http://redis.io/commands/zrem) call.
