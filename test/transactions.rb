# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

class Post < Ohm::Model
  attribute :body
  attribute :state
  index :state

  def before_save
    self.body = body.to_s.strip
  end

  def before_create
    self.state = "draft"
  end
end

setup do
  Post.db
end

test do |redis|
  p = Post.new(body: " foo ")

  redis.set "csv:foo", "A,B"

  t1 = Ohm::Transaction.define do |t|
    t.watch("csv:foo")
  
    csv = nil

    t.read do
      csv = redis.get("csv:foo")
    end

    t.write do
      redis.set("csv:foo", csv + "," + "C")
    end
  end

  main = Ohm::Transaction.new(p.create_transaction, t1)
  main.commit(redis)

  # Verify the Post transaction proceeded without a hitch
  p = Post[p.id]
  assert_equal "draft", p.state
  assert_equal "foo", p.body
  assert Post.find(state: "draft").include?(p)

  # Verify that the second transaction happened
  assert_equal "A,B,C", redis.get("csv:foo")
end
