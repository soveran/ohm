require_relative "helper"

module Foo
  class User < Ohm::Model
    collection :posts, :'Foo::Post'
  end

  class Post < Ohm::Model
    reference :user, :'Foo::User'
  end
end

setup do
  u = Foo::User.create
  p = Foo::Post.create(:user => u)

  [u, p]
end

test "forward association" do |u, p|
  assert u.posts.include?(p)

  p = Foo::Post[p.id]
  assert_equal u, p.user
end
