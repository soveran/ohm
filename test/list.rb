require File.expand_path("./helper", File.dirname(__FILE__))

class Post < Ohm::Model
  list :comments, :Comment
end

class Comment < Ohm::Model
end

setup do
  post = Post.create

  post.comments.push(c1 = Comment.create)
  post.comments.push(c2 = Comment.create)
  post.comments.push(c3 = Comment.create)

  [post, c1, c2, c3]
end

test "include?" do |p, c1, c2, c3|
  assert p.comments.include?(c1)
  assert p.comments.include?(c2)
  assert p.comments.include?(c3)
end

test "first / last / size / empty?" do |p, c1, c2, c3|
  assert_equal 3, p.comments.size
  assert_equal c1, p.comments.first
  assert_equal c3, p.comments.last
  assert ! p.comments.empty?
end

test "replace" do |p, c1, c2, c3|
  c4 = Comment.create

  p.comments.replace([c4])

  assert_equal [c4], p.comments.to_a
end

test "push / unshift" do |p, c1, c2, c3|
  c4 = Comment.create
  c5 = Comment.create

  p.comments.unshift(c4)
  p.comments.push(c5)

  assert_equal c4, p.comments.first
  assert_equal c5, p.comments.last
end

test "delete" do |p, c1, c2, c3|
  p.comments.delete(c1)
  assert_equal 2, p.comments.size
  assert ! p.comments.include?(c1)

  p.comments.delete(c2)
  assert_equal 1, p.comments.size
  assert ! p.comments.include?(c2)

  p.comments.delete(c3)
  assert p.comments.empty?
end

test "deleting main model cleans up the collection" do |p, _, _, _|
  p.delete

  assert ! Ohm.redis.exists(p.key[:comments])
end
