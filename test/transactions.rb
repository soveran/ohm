# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))
require "ohm/transaction"

prepare do
  Ohm.redis.del("foo")
end

setup do
  Ohm.redis
end

test "basic functionality" do |db|
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

test "new returns a transaction" do |db|
  t1 = Ohm::Transaction.new do |t|
    t.write do
      db.set("foo", "bar")
    end
  end

  t1.commit(db)

  assert_equal "bar", db.get("foo")
end

test "transaction local storage" do |db|
  t1 = Ohm::Transaction.new do |t|
    t.read do |s|
      s.foo = db.type("foo")
    end

    t.write do |s|
      db.set("foo", s.foo.reverse)
    end
  end

  t1.commit(db)

  assert_equal "enon", db.get("foo")
end

test "composed transaction" do |db|
  t1 = Ohm::Transaction.new do |t|
    t.watch("foo")

    t.write do |s|
      db.set("foo", "bar")
    end
  end

  t2 = Ohm::Transaction.new do |t|
    t.watch("foo")

    t.write do |s|
      db.set("foo", "baz")
    end
  end

  t3 = Ohm::Transaction.new
  t3.append(t1)
  t3.append(t2)
  t3.commit(db)

  assert_equal "baz", db.get("foo")

  t4 = Ohm::Transaction.new
  t4.append(t2)
  t4.append(t1)
  t4.commit(db)

  assert_equal "bar", db.get("foo")

  t5 = Ohm::Transaction.new
  t5.append(t4)
  t5.commit(db)

  assert_equal "bar", db.get("foo")

  assert_equal ["foo"], t5.phase[:watch]
  assert_equal 2, t5.phase[:write].size
end

test "composing transactions with append" do |db|
  t1 = Ohm::Transaction.new do |t|
    t.write do
      db.set("foo", "bar")
    end
  end

  t2 = Ohm::Transaction.new do |t|
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

test "appending or prepending is determined by when append is called" do |db|
  t1 = Ohm::Transaction.new do |t|
    t.write do
      db.set("foo", "bar")
    end
  end

  t2 = Ohm::Transaction.new do |t|
    t.append(t1)

    t.write do
      db.set("foo", "baz")
    end
  end

  t3 = Ohm::Transaction.new do |t|
    t.write do
      db.set("foo", "baz")
    end

    t.append(t1)
  end

  t2.commit(db)

  assert_equal "baz", db.get("foo")

  t3.commit(db)

  assert_equal "bar", db.get("foo")
end

test "storage in composed transactions" do |db|
  t1 = Ohm::Transaction.new do |t|
    t.read do |s|
      s.foo = db.type("foo")
    end
  end

  t2 = Ohm::Transaction.new do |t|
    t.write do |s|
      db.set("foo", s.foo.reverse)
    end
  end

  t1.append(t2).commit(db)

  assert_equal "enon", db.get("foo")
end

test "storage entries can't be overriden" do |db|
  t1 = Ohm::Transaction.new do |t|
    t.read do |s|
      s.foo = db.type("foo")
    end
  end

  t2 = Ohm::Transaction.new do |t|
    t.read do |s|
      s.foo = db.exists("foo")
    end
  end

  assert_raise Ohm::Transaction::Store::EntryAlreadyExistsError do
    t1.append(t2).commit(db)
  end
end

__END__
# We leave this here to indicate what the past behavior was with
# model transactions.

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

test "transactions in models" do |db|
  p = Post.new(body: " foo ")

  db.set "csv:foo", "A,B"

  t1 = Ohm::Transaction.define do |t|
    t.watch("csv:foo")

    t.read do |s|
      s.csv = db.get("csv:foo")
    end

    t.write do |s|
      db.set("csv:foo", s.csv + "," + "C")
    end
  end

  main = Ohm::Transaction.new(p.transaction_for_create, t1)
  main.commit(db)

  # Verify the Post transaction proceeded without a hitch
  p = Post[p.id]

  assert_equal "draft", p.state
  assert_equal "foo", p.body
  assert Post.find(state: "draft").include?(p)

  # Verify that the second transaction happened
  assert_equal "A,B,C", db.get("csv:foo")
end
