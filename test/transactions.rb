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
      s[:foo] = db.type("foo")
    end

    t.write do |s|
      db.set("foo", s[:foo].reverse)
    end
  end

  t1.commit(db)

  assert_equal "enon", db.get("foo")
end

test "composed transaction" do |db|
  t1 = Ohm::Transaction.new do |t|
    t.watch("foo")

    t.write do
      db.set("foo", "bar")
    end
  end

  t2 = Ohm::Transaction.new do |t|
    t.watch("foo")

    t.write do
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
      s[:foo] = db.type("foo")
    end
  end

  t2 = Ohm::Transaction.new do |t|
    t.write do |s|
      db.set("foo", s[:foo].reverse)
    end
  end

  t1.append(t2).commit(db)

  assert_equal "enon", db.get("foo")
end

test "reading an storage entries that doesn't exist raises" do |db|
  t1 = Ohm::Transaction.new do |t|
    t.read do |s|
      s[:foo]
    end
  end

  assert_raise Ohm::Transaction::Store::NoEntryError do
    t1.commit(db)
  end
end

test "storage entries can't be overriden" do |db|
  t1 = Ohm::Transaction.new do |t|
    t.read do |s|
      s[:foo] = db.type("foo")
    end
  end

  t2 = Ohm::Transaction.new do |t|
    t.read do |s|
      s[:foo] = db.exists("foo")
    end
  end

  assert_raise Ohm::Transaction::Store::EntryAlreadyExistsError do
    t1.append(t2).commit(db)
  end
end

test "banking transaction" do |db|
  class A < Ohm::Model
    attribute :amount
  end

  class B < Ohm::Model
    attribute :amount
  end

  def transfer(amount, account1, account2)
    Ohm.transaction do |t|

      t.watch(account1.key, account2.key)

      t.read do |s|
        s[:available] = account1.get(:amount).to_i
      end

      t.write do |s|
        if s[:available] >= amount
          account1.key.hincrby(:amount, - amount)
          account2.key.hincrby(:amount,   amount)
        end
      end
    end
  end

  a = A.create :amount => 100
  b = B.create :amount => 0

  transfer(100, a, b).commit(db)

  assert_equal a.get(:amount), "0"
  assert_equal b.get(:amount), "100"
end
