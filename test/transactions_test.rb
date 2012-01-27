# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

db = Ohm.redis

prepare do
  db.del("foo")
end

test "basic functionality" do
  t = Ohm::Transaction.new
  x = nil

  t.watch("foo")

  t.read do
    x = db.get("foo")
  end

  t.write do
    db.set("foo", x.to_i + 2)
  end

  t.commit(db)

  assert_equal "2", db.get("foo")
end

test "composed transaction" do
  t1 = Ohm::Transaction.new
  t2 = Ohm::Transaction.new

  x = nil

  t1.watch("foo")

  t1.read do
    x = db.get("foo")
  end

  t1.write do
    db.set("foo", x.to_i + 2)
  end

  t2.watch("foo")

  t2.read do
    x = db.get("foo")
  end

  t2.write do
    db.set("foo", x.to_i + 3)
  end

  t3 = Ohm::Transaction.new(t1, t2)
  t3.commit(db)

  assert_equal "3", db.get("foo")

  t4 = Ohm::Transaction.new(t2, t1)
  t4.commit(db)

  assert_equal "5", db.get("foo")

  t5 = Ohm::Transaction.new(t4)
  t5.commit(db)

  assert_equal "7", db.get("foo")

  assert_equal Set.new(["foo"]), t5.phase[:watch]
  assert_equal 2, t5.phase[:read].size
  assert_equal 2, t5.phase[:write].size
end

test "define" do
  t1 = Ohm::Transaction.define do |t|
    v = nil
    t.watch("foo")

    t.read do
      v = db.type("foo")
    end

    t.write do
      db.set("foo", v)
    end
  end

  t1.commit(db)

  assert_equal "none", db.get("foo")
  assert_equal "string", db.type("foo")
end

test "append" do
  t1 = Ohm::Transaction.define do |t|
    t.write do
      db.set("foo", "bar")
    end
  end

  t2 = Ohm::Transaction.define do |t|
    t.write do
      db.set("foo", "baz")
    end
  end

  t1.append(t2)
  t1.commit(db)

  assert_equal "baz", db.get("foo")

  t2.append(t1)
  t2.commit(db)

  assert_equal "bar", db.get("foo")
end

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
