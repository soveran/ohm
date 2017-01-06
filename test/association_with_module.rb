require_relative "helper"

module Blog
  class User < Ohm::Model
    collection :posts, :'Blog::Post'
  end
  
  class Post < Ohm::Model
    reference :user, :'Blog::User'
  end
end

setup do
  u = Blog::User.create
  p = Blog::Post.create(:user => u)

  [u, p]
end

test "basic shake and bake" do |u, p|
  assert u.posts.include?(p)

  p = Blog::Post[p.id]
  assert_equal u, p.user
end

test "memoization" do |u, p|
  # This will read the user instance once.
  p.user
  assert_equal p.user, p.instance_variable_get(:@_memo)[:user]

  # This will un-memoize the user instance
  p.user = u
  assert_equal nil, p.instance_variable_get(:@_memo)[:user]
end
