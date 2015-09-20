### Tagging

#### Intro

# When building a Web 2.0 application, tagging will probably come up
# as one of the most requested features. Popularized by Delicious,
# it has quickly become a useful way to organize crowd sourced data.

#### How it was done

# Typically, when you do tagging using an RDBMS, you'll probably end up
# having a taggings and a tags table, hence a many-to-many design.
# Here is a quick sketch just to illustrate:
#
#
#
#     Post      Taggings      Tag
#     ----      --------      ---
#     id        tag_id        id
#     title     post_id       name
#
# As you can see, this design leads to a lot of problems:
#
# 1. Trying to find the tags of a post will have to go through taggings, and
#    then individually find the actual tag.
# 2. One might be inclined to use a JOIN query, but we all know
#    [joins are evil](http://stackoverflow.com/questions/1020847).
# 3. Building a tag cloud or some form of tag ranking is unintuitive.

#### The Ohm approach

# Here is a basic outline of what we'll need:
#
# 1.  We should be able to tag a post (separated by commas).
# 2.  We should be able to find a post with a given tag.

#### Beginning with our Post model

# Let's first require ohm.
require 'ohm'

# We then declare our class, inheriting from `Ohm::Model` in the process.
class Post < Ohm::Model

  # The structure, fields, and other associations are defined in a declarative
  # manner. Ohm allows us to declare *attributes*, *sets*, *lists* and
  # *counters*. For our usecase here, only two *attributes* will get the job
  # done. The `body` will just
  # be a plain string, and the `tags` will contain our comma-separated list of
  # words, i.e. "ruby, redis, ohm". We then declare an `index` (which can be
  # an `attribute` or just a plain old method), which we point to our method
  # `tag`.
  attribute :body
  attribute :tags
  index :tag

  # One very interesting thing about Ohm indexes is that it can either be a
  # *String* or an *Enumerable* data structure. When we declare it as an
  # *Enumerable*, `Ohm` will create an index for every element. So if `tag`
  # returned `[ruby, redis, ohm]` then we can search it using any of the
  # following:
  #
  # 1. ruby
  # 2. redis
  # 3. ohm
  # 4. ruby, redis
  # 5. ruby, ohm
  # 6. redis, ohm
  # 7. ruby, redis, ohm
  #
  # Pretty neat ain't it?
  def tag
    tags.to_s.split(/\s*,\s*/).uniq
  end
end

#### Testing it out

# It's a very good habit to test all the time. In the Ruby community,
# a lot of test frameworks have been created.

# For our purposes in this example, we'll use cutest.
require "cutest"

# Cutest allows us to define callbacks which are guaranteed to be executed
# every time a new `test` begins. Here, we just make sure that the Redis
# instance of `Ohm` is empty everytime.
prepare { Ohm.flush }

# Next, let's create a simple `Post` instance. The return value of the `setup`
# block will be passed to every `test` block, so we don't actually have to
# assign it to an instance variable.
setup do
  Post.create(:body => "Ohm Tagging", :tags => "tagging, ohm, redis")
end

# For our first run, let's verify the fact that we can find a `Post`
# using any of the tags we gave.
test "find using a single tag" do |p|
  assert Post.find(tag: "tagging").include?(p)
  assert Post.find(tag: "ohm").include?(p)
  assert Post.find(tag: "redis").include?(p)
end

# Now we verify our claim earlier, that it is possible to find a tag
# using any one of the combinations for the given set of tags.
#
# We also verify that if we pass in a non-existent tag name that
# we'll fail to find the `Post` we just created.
test "find using an intersection of multiple tag names" do |p|
  assert Post.find(tag: ["tagging", "ohm"]).include?(p)
  assert Post.find(tag: ["tagging", "redis"]).include?(p)
  assert Post.find(tag: ["ohm", "redis"]).include?(p)
  assert Post.find(tag: ["tagging", "ohm", "redis"]).include?(p)

  assert ! Post.find(tag: ["tagging", "foo"]).include?(p)
end

#### Adding a Tag model

# Let's pretend that the client suddenly requested that we keep track
# of the number of times a tag has been used. It's a pretty fair requirement
# after all. Updating our requirements, we will now have:
#
# 1.  We should be able to tag a post (separated by commas).
# 2.  We should be able to find a post with a given tag.
# 3.  We should be able to find top tags, and their count.

# Continuing from our example above, let's require `ohm-contrib`, which we
# will be using for callbacks.
require "ohm/contrib"

# Let's quickly re-open our Post class.
class Post
  # When we want our class to have extended functionality like callbacks,
  # we simply include the necessary modules, in this case `Ohm::Callbacks`,
  # which will be responsible for inserting `before_*` and `after_*` methods
  # in the object's lifecycle.
  include Ohm::Callbacks

  # To make our code more concise, we just quickly change our implementation
  # of `tag` to receive a default parameter:
  def tag(tags = self.tags)
    tags.to_s.split(/\s*,\s*/).uniq
  end

  # For all but the most simple cases, we would probably need to define
  # callbacks. When we included `Ohm::Callbacks` above, it actually gave us
  # the following:
  #
  # 1. `before_validate` and `after_validate`
  # 2. `before_create` and `after_create`
  # 3. `before_update` and `after_update`
  # 4. `before_save` and `after_save`
  # 5. `before_delete` and `after_delete`

  # For our scenario, we only need a `before_update` and `after_save`.
  # The idea for our `before_update` is to decrement the `total` of
  # all existing tags. We use `get(:tags)` the original tags for the
  # record and use assigned one on save.
protected
  def before_update
    assigned_tags = tags
    tag(get(:tags)).map(&Tag).each { |t| t.decrement :total }
    self.tags = assigned_tags
  end

  # And of course, we increment all new tags for a particular record
  # after successfully saving it.
  def after_save
    tag.map(&Tag).each { |t| t.increment :total }
  end
end

#### Our Tag model

# The `Tag` model has only one type, which is a `counter` for the `total`.
# Since `Ohm` allows us to use any kind of ID (not just numeric sequences),
# we can actually use the tag name to identify a `Tag`.
class Tag < Ohm::Model
  counter :total

  # The syntax for finding a record by its ID is `Tag["ruby"]`. The standard
  # behavior in `Ohm` is to return `nil` when the ID does not exist.
  #
  # To simplify our code, we override `Tag["ruby"]`, and make it create a
  # new `Tag` if it doesn't exist yet. One important implementation detail
  # though is that we need to encode the tag name, so special characters
  # and spaces won't produce an invalid key.
  def self.[](id)
    encoded_id = id.encode
    super(encoded_id) || create(:id => encoded_id)
  end
end

#### Verifying our third requirement

# Continuing from our test cases above, let's add test coverage for the
# behavior of counting tags.

# For each and every tag we initially create, we need to make sure they have a
# total of 1.
test "verify total to be exactly 1" do
  assert 1 == Tag["ohm"].total
  assert 1 == Tag["redis"].total
  assert 1 == Tag["tagging"].total
end

# If we try and create another post tagged "ruby", "redis", `Tag["redis"]`
# should then have a total of 2. All of the other tags will still have
# a total of 1.
test "verify totals increase" do
  Post.create(:body => "Ruby & Redis", :tags => "ruby, redis")

  assert 1 == Tag["ohm"].total
  assert 1 == Tag["tagging"].total
  assert 1 == Tag["ruby"].total
  assert 2 == Tag["redis"].total
end

# Finally, let's verify the scenario where we create a `Post` tagged
# "ruby", "redis" and update it to only have the tag "redis",
# effectively removing the tag "ruby" from our `Post`.
test "updating an existing post decrements the tags removed" do
  p = Post.create(:body => "Ruby & Redis", :tags => "ruby, redis")
  p.update(:tags => "redis")

  assert 0 == Tag["ruby"].total
  assert 2 == Tag["redis"].total
end

## Conclusion

# Most of the time we tend to think in terms of an RDBMS way, and this is in
# no way a negative thing. However, it is important to try and switch your
# frame of mind when working with Ohm (and Redis) because it will greatly save
# you time, and possibly lead to a great design.
