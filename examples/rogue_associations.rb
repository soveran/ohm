# This attempts to illustrate the redis way of...
#   - has_one 1:1 (Rogue - equipment)
#   - has_many through (Rogue - inventory) 1:1 many:many 1:1
#   - has_one 1:many (equipment - item)
#   - Mixin usage to promote DRY code

require "ohm"

def battleable
  attribute :name;       index :name
  attribute :hp,         lambda { |x| x.to_i } # cast hp to integer
  attribute :mp,         lambda { |x| x.to_i }
  list      :inventory,  :Item

  attribute :equipment_id
  reference :equipment,  :Loadout
end

# We define both a `Video` and `Audio` model, with a `list` of *comments*.
class Rogue < Ohm::Model
  battleable # give Rogues all the attributes required to conduct battle

  # instead of using Rogue.create, favor Rogue.spawn
  def self.spawn(name: nil)
    rogue = self.create(name: name)
    rogue.equipment = Loadout.create
    rogue.save
    rogue
  end
end

class Monster < Ohm::Model
  battleable # give monsters attributes required to conduct battle


end

class Loadout < Ohm::Model
  attribute :head_id
  reference :head,       :Item
  attribute :right_hand_id
  reference :right_hand, :Item
  attribute :left_hand_id
  reference :left_hand,  :Item
  attribute :body_id
  reference :body,       :Item
  attribute :legs_id
  reference :legs,       :Item
  attribute :feet_id
  reference :feet,       :Item
  attribute :wrist_id
  reference :wrist,      :Item
  attribute :neck_id
  reference :neck,       :Item
end

class Item < Ohm::Model
  attribute :name
  attribute :dmg,    lambda { |x| x.to_i }
  attribute :def,    lambda { |x| x.to_i }
  attribute :value,  lambda { |x| x.to_i }

  def sell_to(target)
    original_owner = "hmmm...."
  end
end




# Now let's require the test framework we're going to use called
# [cutest](http://github.com/djanowski/cutest)
require "cutest"


# And make sure that every run of our test suite has a clean Redis instance.
prepare { Ohm.flush }

test "a rogue can be equipped with leggins" do
  rogue = Rogue.spawn

  rogue.equipment.legs = Item.create(name: "Starting Leggings", def: "1")

  # TODO: Should I do something to make saving a parent also save children?
  rogue.save
  rogue.equipment.save

  rogue = Rogue[rogue.id] # lookup the rogue from the DB to make sure things are persistent
  assert_equal rogue.equipment.legs.def, 1
end

test "a rogue can sell her gear" do
  rogue = Rogue.spawn


end
