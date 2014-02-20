require_relative "helper"

class Model < Ohm::Model
  attribute :hash
  index :hash

  attribute :data
end

test do
  50.times do |i|
    Ohm.flush

    Model.create(:hash => "123")

    assert_equal 1, Ohm.redis.call("SCARD", "Model:all")

    Thread.new do
      a = Model.find(:hash => "123").first
      a.update(:data => "2")
    end

    sleep 0.01

    b = Model.find(:hash => "123").first

    if Ohm.redis.call("SCARD", "Model:indices:hash:123") != 1
      flunk("Failed at iteration %d" % i)
    end

    assert ! b.nil?
  end
end

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
