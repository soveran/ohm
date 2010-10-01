### All Kinds of Slugs

# The problem of making semantic URLs have definitely been a prevalent one.
# There has been quite a lot of solutions around this theme, so we'll discuss
# a few simple ways to handle slug generation.

#### ID Prefixed slugs

# This is by far the simplest (and most cost-effective way) of generating
# slugs. Implementing this is pretty simple too.

# Let's first require `Ohm`.
require "ohm"

# Now let's define our `Post` model, with just a single
# `attribute` *title*.
class Post < Ohm::Model
  attribute :title

  # To make it more convenient, we override the finder syntax,
  # so doing a `Post["1-my-post-title"]` will in effect just call
  # `Post[1]`.
  def self.[](id)
    super(id.to_i)
  end

  # This pattern was mostly borrowed from Rails' style of generating
  # URLs. Here we just concatenate the `id` and a sanitized form
  # of our title.
  def to_param
    "#{id}-#{title.to_s.gsub(/\p{^Alnum}/u, " ").gsub(/\s+/, "-").downcase}"
  end
end

# Let's verify our code using the
# [Cutest](http://github.com/djanowski/cutest)
# testing framework.
require "cutest"

# Also we ensure every test run is guaranteed to have a clean
# *Redis* instance.
prepare { Ohm.flush }

# For each and every test, we create a post with
# the title "ID Prefixed Slugs". Since it's the last
# line of our `setup`, it will also be yielded to
# each of our test blocks.
setup do
  Post.create(:title => "ID Prefixed Slugs")
end

# Now let's verify the behavior of our `to_param` method.
# Note that we make it dash-separated and lowercased.
test "to_param" do |post|
  assert "1-id-prefixed-slugs" == post.to_param
end

# We also check that our easier finder syntax works.
test "finding the post" do |post|
  assert post == Post[post.to_param]
end

#### We don't have to code it everytime

# Because of the prevalence, ease of use, and efficiency of this style of slug
# generation, it has been extracted to a module in
# [Ohm::Contrib](http://github.com/cyx/ohm-contrib/) called `Ohm::Slug`.

# Let's create a different model to demonstrate how to use it.
# (Run `[sudo] gem install ohm-contrib` to install ohm-contrib).

# When using `ohm-contrib`, we simply require it, and then
# directly reference the specific module. In this case, we
# use `Ohm::Slug`.
require "ohm/contrib"

class Video < Ohm::Model
  include Ohm::Slug

  attribute :title

  # `Ohm::Slug` just uses the value of the object's `to_s`.
  def to_s
    title.to_s
  end
end

# Now to quickly verify that everything works similar to our
# example above!
test "video slugging" do
  video = Video.create(:title => "A video about ohm")

  assert "1-a-video-about-ohm" == video.to_param
  assert video == Video[video.id]
end

# That's it, and it works similarly to the example above.

#### What if I want a slug without an ID prefix?

# For this case, we can still make use of `Ohm::Slug`'s ability to
# make a clean string.

# Let's create an `Article` class which has a single attribute `title`.
class Article < Ohm::Model
  include Ohm::Callbacks

  attribute :title

# Now before creating this object, we just call `Ohm::Slug.slug` directly.
# We also check if the generated slug exists, and repeatedly try
# appending numbers.
protected
  def before_create
    temp = Ohm::Slug.slug(title)
    self.id = temp

    counter = 0
    while Article.exists?(id)
      self.id = "%s-%d" % [temp, counter += 1]
    end
  end
end

# We now verify the behavior of our `Article` class
# by creating an article with the same title 3 times.
test "create an article with the same title" do
  a1 = Article.create(:title => "All kinds of slugs")
  a2 = Article.create(:title => "All kinds of slugs")
  a3 = Article.create(:title => "All kinds of slugs")

  assert a1.id == "all-kinds-of-slugs"
  assert a2.id == "all-kinds-of-slugs-1"
  assert a3.id == "all-kinds-of-slugs-2"
end

#### Conclusion

# Slug generation comes in all different flavors.
#
# 1. The first solution is good enough for most cases. The primary advantage
#    of this solution is that we don't have to check for ID clashes.
#
# 2. The second solution may be needed for cases where you must make
#    the URLs absolutely clean and readable, and you hate having those
#    number prefixes.
#
#    *NOTE:* The example we used for the second solution has potential
#    race conditions. I'll leave fixing it as an exercise to you.
