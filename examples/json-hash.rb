### Make Peace wih JSON and Hash

#### Why do I care?

# If you've ever needed to build an AJAX route handler, you may have noticed
# the prevalence of the design pattern where you return a JSON response.
#
#     post "/comments.json" do
#       comment = Comment.create(params[:comment])
#       comment.to_json
#     end
#
# `Ohm` helps you here by providing sensible defaults. It's not very popular,
# but `Ohm` actually has a `to_hash` method.

# Let's start by requiring `ohm` and `json`. In ruby 1.9, `json` is
# actually part of the standard library, so you don't have to install a gem
# for it. For ruby 1.8.x, a simple `[sudo] gem install json` will do it.
require "ohm"
require "json"

# Here we define our `Post` model with just a single `attribute` called
# `title`.
#
# We also define a validation, asserting the presence of the `title`.
class Post < Ohm::Model
  attribute :title

  def validate
    assert_present :title
  end
end

# Now let's load the test framework `cutest` to verify our code. We
# also call `Ohm.flush` for each test run.
require "cutest"

prepare { Ohm.flush }

# When we successfully create a `Post`, we can see that it returns
# only the *id* and its value in the hash.
test "hash representation when created" do
  post = Post.create(:title => "my post")

  assert({ :id => "1" } == post.to_hash)
end

# The JSON representation is actually just `post.to_hash.to_json`, so the
# same result, only in JSON, is returned.
test "json representation when created" do
  post = Post.create(:title => "my post")

  assert("{\"id\":\"1\"}" == post.to_json)
end

# Let's try and do the opposite now -- that is, purposely try and create
# an invalid `Post`. We can see that it returns the `errors` of the
# `Post`, because we added an `assert_present :title` in our code above.
test "hash representation when validation failed" do
  post = Post.create

  assert({ :errors => [[:title, :not_present]]} == post.to_hash)
end

# As is the case for a valid record, the JSON representation is
# still equivalent to `post.to_hash.to_json`.
test "json representation when validation failed" do
  post = Post.create

  assert("{\"errors\":[[\"title\",\"not_present\"]]}" == post.to_json)
end

#### Whitelisted approach

# Unlike in other frameworks which dumps out all attributes by default,
# `Ohm` favors a whitelisted approach where you have to explicitly
# declare which attributes you want.
#
# By default, only `:id` and `:errors` will be available, depending if
# it was successfully saved or if there were validation errors.

# Let's re-open our Post class, and add a `to_hash` method.
class Post
  def to_hash
    super.merge(:title => title)
  end
end

# Now, let's test that the title is in fact part of `to_hash`.
test "customized to_hash" do
  post = Post.create(:title => "Override FTW?")
  assert({ :id => "1", :title => "Override FTW?" } == post.to_hash)
end

#### Conclusion

# Ohm has a lot of neat intricacies like this. Some of the things to keep
# in mind from this tutorial would be:
#
# 1. `Ohm` doesn't assume too much about your needs.
# 2. If you need a customized version, you can always define it yourself.
# 3. Customization is easy using basic OOP principles.
