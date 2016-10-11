require_relative "helper"
require_relative "../lib/ohm/tags"

class Post < Ohm::Model
  include Ohm::Tags
end

setup do
  Post.create
end

test "tagging" do |post|
  foo = Post.find(tag: "foo")
  bar = Post.find(tag: "bar")

  assert_equal 0, foo.size
  assert_equal 0, bar.size

  assert_equal nil, foo.first
  assert_equal nil, bar.first

  post.tag! "foo"

  assert_equal 1, foo.size
  assert_equal 0, bar.size

  assert_equal post, foo.first
  assert_equal nil,  bar.first

  post.tag! "bar"

  assert_equal 1, foo.size
  assert_equal 1, bar.size

  assert_equal post, foo.first
  assert_equal post, bar.first
end

setup do
  Post.create(:tags => "foo bar")
end

test "untagging" do |post|
  foo = Post.find(tag: "foo")
  bar = Post.find(tag: "bar")

  assert_equal 1, foo.size
  assert_equal 1, bar.size

  assert_equal post, foo.first
  assert_equal post, bar.first

  post.untag! "bar"

  assert_equal 1, foo.size
  assert_equal 0, bar.size

  assert_equal post, foo.first
  assert_equal nil,  bar.first
end
