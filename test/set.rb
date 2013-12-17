require_relative 'helper'

class Post < Ohm::Model
end

class User < Ohm::Model
  set :posts, :Post
end

test '#exists? returns false if the given id is not included in the set' do
  assert !User.create.posts.exists?('nonexistent')
end

test '#exists? returns true if the given id is included in the set' do
  user = User.create
  post = Post.create
  user.posts.add(post)

  assert user.posts.exists?(post.id)
end
