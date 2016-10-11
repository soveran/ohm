require_relative "helper"
require_relative "../lib/ohm/namespace"

class User < Ohm::Model
  collection :posts, :Post

  def self.name
    "{foo}::#{super}"
  end
end

class Post < Ohm::Model
  extend Ohm::Namespace
  
  namespace :foo
  reference :user, :User
end

setup do
  user = User.create
  post = Post.create(:user => user)

  [user, post]
end

test do |user, post|
  assert_equal "{foo}::User", User.name
  assert_equal "{foo}::Post", Post.name

  assert user.posts.include?(post)
  assert_equal user, post.user
end
