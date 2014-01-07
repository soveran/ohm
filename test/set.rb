require_relative 'helper'

class Post < Ohm::Model
end

class User < Ohm::Model
  attribute :name

  index :name

  set :posts, :Post
end

test "#exists? returns false if the given id is not included in the set" do
  assert !User.create.posts.exists?('nonexistent')
end

test "#exists? returns true if the given id is included in the set" do
  user = User.create
  post = Post.create
  user.posts.add(post)

  assert user.posts.exists?(post.id)
end

test "converts ids of resulting records to integers " do
  user_ids = [
    user1 = User.create(name: "John"),
    user2 = User.create(name: "Jane")
  ].map(&:id)

  assert_equal user_ids, User.all.map(&:id)

  result = User.find(name: user1.name).union(name: user2.name)

  assert_equal user_ids, result.map(&:id)
end
