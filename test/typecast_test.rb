
require File.expand_path("./helper", File.dirname(__FILE__))

require "ostruct"

class Multi < Ohm::Model
  attribute :body
  # string :foo
  number :lottery
  decimal :prize
#  time :at
  # date :frox
  # float :fru
  # json :rox
  # bson


  list :related, Post
end




test "assign attributes as numbers" do
  multi = Multi.new(:lottery => 88)
  assert multi.lottery == 88
end

test "assign attributes as decimals" do
  multi = Multi.new(:prize => 88.99)
  assert multi.prize == 88.99
end

# test "assign attributes as timestamps" do
#   t = Time.now
#   multi = Multi.new(:at => t)
#   assert multi.at == t
# end

# test "assign an ID and save the object" do
#   multi1 = Multi.create(:name => "Ruby Tuesday")
#   multi2 = Multi.create(:name => "Ruby Meetup")

#   assert "1" == multi1.id
#   assert "2" == multi2.id
# end

# test "return the unsaved object if validation fails" do
#   assert Person.create(:name => nil).kind_of?(Person)
# end
