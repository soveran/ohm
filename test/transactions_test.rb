# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

db = Ohm.redis

prepare do
  db.del("foo")
end

test do
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

test do
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

  assert_equal Set.new(["foo"]), t5.observed_keys
  assert_equal 2, t5.reading_procs.size
  assert_equal 2, t5.writing_procs.size
end

test do
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
