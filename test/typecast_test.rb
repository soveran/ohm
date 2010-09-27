
require File.expand_path("./helper", File.dirname(__FILE__))

require "ostruct"
# class WoW;  end

class Multi < Ohm::Model
  attribute :body
  attr :test

  string :foo
  number :lottery
  decimal :prize
  time :event
  stamp :created_at

  json :sh
  # marshal :obj, WoW bad idea...?
  # date :frox
  # float :fru
  # json :rox
  # bson
end


test "assign attributes as numbers" do
  multi = Multi.new(:foo => "Hey!")
  assert multi.foo == "Hey!"
end

test "assign attributes as numbers" do
  multi = Multi.new(:lottery => 88)
  assert multi.lottery == 88
end

test "assign attributes as decimals" do
  multi = Multi.new(:prize => 88.99)
  assert multi.prize == 88.99
end

test "assign attributes as time" do
  t = Time.now
  multi = Multi.new(:event => t)
  assert multi.event == t
end

test "assign attributes as timestamps" do
  t = Time.now
  multi = Multi.new(:created_at => t)
  multi.save
  m = Multi[1]
  assert m.created_at == t.utc.to_i
end

test "assign attributes as hashes" do
  hsh = { "a" => 1, "b" => 2 }
  multi = Multi.new(:sh => hsh)
  multi.save
  m = Multi[1]
  assert m.sh == hsh
end

# test "assign attributes as marshalized objects" do
#   w = WoW.new
#   multi = Multi.new(:obj => w)
#   multi.save
#   assert m.obj == w
# end

