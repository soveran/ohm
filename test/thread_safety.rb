require_relative "helper"

class Post < Ohm::Model; end
class Role < Ohm::Model; end

class User < Ohm::Model
  list :posts, :Post
  set  :roles, :Role
end

setup do
  User.create
end

test "list#replace" do |user|
  Post.mutex.lock

  thread = Thread.new { user.posts.replace([Post.create]) }

  sleep 0.1

  assert_equal true, thread.alive?

  Post.mutex.unlock

  sleep 0.1

  assert_equal false, thread.alive?

  thread.join
end

test "set#replace" do |user|
  Role.mutex.lock

  thread = Thread.new { user.roles.replace([Role.create]) }

  sleep 0.1

  assert_equal true, thread.alive?

  Role.mutex.unlock

  sleep 0.1

  assert_equal false, thread.alive?

  thread.join
end

test "collection#fetch" do
  User.mutex.lock

  thread = Thread.new { User.all.to_a }

  sleep 0.1

  assert_equal true, thread.alive?

  User.mutex.unlock

  sleep 0.1

  assert_equal false, thread.alive?

  thread.join
end
