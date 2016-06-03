# This attempts to illustrate the redis way of...
#   - has_one 1:1 (Rogue - equipment)
#   - has_many through (Rogue - inventory) 1:1 many:many 1:1
#   - has_one 1:many (equipment - item)
#   - Mixin usage to promote DRY code

require "ohm"

def battleable
  attribute :name;       index :name
  attribute :hp
  attribute :mp
  list :inventory, :Item

  reference :equipment, :Loadout
end


# We define both a `Video` and `Audio` model, with a `list` of *comments*.
class Rogue < Ohm::Model
  battleable # give Rogues all the attributes required to conduct battle
end

class Monster < Ohm::Model
  battleable # give monsters attributes required to conduct battle
end

class Loadout < Ohm::Model
  reference :head,       :Item
  reference :right_hand, :Item
  reference :left_hand,  :Item
  reference :body,       :Item
  reference :legs,       :Item
  reference :feet,       :Item
  reference :wrist,      :Item
  reference :neck,       :Item
end

class Item < Ohm::Model
  attribute :name
  attribute :dmg
  attribute :def
  attribute :value
end


# Now let's require the test framework we're going to use called
# [cutest](http://github.com/djanowski/cutest)
require "cutest"

# And make sure that every run of our test suite has a clean Redis instance.
prepare { Ohm.flush }

test "all works" do
  rogue = Rogue.create

  # TODO: can this be initialized on creation of a Rogue?
  rogue.equipment = Loadout.create

  # TODO:
  #  1) Can 'starting leggins' come automatic?
  #  2) Is there a find_or_create method available so users don't wind up
  #     making an ineffient qty of Items?
  rogue.equipment.legs = Item.create(name: "Starting Leggings", def: "1")

  # assert_equal audio.comments.size, 1
end
