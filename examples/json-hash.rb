### Make Peace wih JSON and Hash

#### Why do I care?

# If you've ever needed to build an AJAX route handler, you may have noticed
# the prevalence of the design pattern where you return a JSON response.
#
#     on get, "comments" do
#       res.write Comment.all.to_json
#     end
#
# `Ohm` helps you here by providing sensible defaults. It's not very popular,
# but `Ohm` actually has a `to_hash` method.

# Let's start by requiring `ohm` and `ohm/json`.
require "ohm"
require "ohm/json"

# Here we define our `Post` model with just a single `attribute` called `title`.
class Post < Ohm::Model
  attribute :title
end

# Now let's load the test framework `cutest` to test our code.
require "cutest"

# We also call `Ohm.flush` for each test run.
prepare { Ohm.flush }

# When we successfully create a `Post`, we can see that it returns
# only the *id* and its value in the hash.
test "hash representation when created" do
  post = Post.create(title: "my post")

  assert_equal Hash[id: post.id], post.to_hash
end

# The JSON representation is actually just `post.to_hash.to_json`, so the
# same result, only in JSON, is returned.
test "json representation when created" do
  post = Post.create(title: "my post")

  assert_equal "{\"id\":\"#{post.id}\"}", post.to_json
end

#### Whitelisted approach

# Unlike other frameworks which dumps out all attributes by default,
# `Ohm` favors a whitelisted approach where you have to explicitly
# declare which attributes you want.
#
# By default, only `:id` will be available if the model is persisted.

# Let's re-open our Post class, and add a `to_hash` method.
class Post
  def to_hash
    super.merge(title: title)
  end
end

# Now, let's test that the title is in fact part of `to_hash`.
test "customized to_hash" do
  post = Post.create(title: "Override FTW?")

  assert_equal Hash[id: post.id, title: post.title], post.to_hash
end

#### Conclusion

# Ohm has a lot of neat intricacies like this. Some of the things to keep
# in mind from this tutorial would be:
#
# 1. `Ohm` doesn't assume too much about your needs.
# 2. If you need a customized version, you can always define it yourself.
# 3. Customization is easy using basic OOP principles.
