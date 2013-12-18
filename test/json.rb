require_relative 'helper'

require "ohm/json"

class Venue < Ohm::Model
  attribute :name
  list :programmers, :Programmer
end

class Programmer < Ohm::Model
  attribute :language

  index :language

  def to_hash
    super.merge(language: language)
  end
end

test "exports model.to_hash to json" do
  assert_equal Hash.new, JSON.parse(Venue.new.to_json)

  venue = Venue.create(name: "foo")
  json  = JSON.parse(venue.to_json)
  assert_equal venue.id, json["id"]
  assert_equal nil, json["name"]

  programmer = Programmer.create(language: "Ruby")
  json = JSON.parse(programmer.to_json)

  assert_equal programmer.id, json["id"]
  assert_equal programmer.language, json["language"]
end

test "exports a set to json" do
  Programmer.create(language: "Ruby")
  Programmer.create(language: "Python")

  expected = [{ id: "1", language: "Ruby" }, { id: "2", language: "Python"}].to_json

  assert_equal expected, Programmer.all.to_json
end

test "exports a multiset to json" do
  Programmer.create(language: "Ruby")
  Programmer.create(language: "Python")

  expected = [{ id: "1", language: "Ruby" }, { id: "2", language: "Python"}].to_json
  result   = Programmer.find(language: "Ruby").union(language: "Python").to_json

  assert_equal expected, result
end

test "exports a list to json" do
  venue = Venue.create(name: "Foo")

  venue.programmers.push(Programmer.create(language: "Ruby"))
  venue.programmers.push(Programmer.create(language: "Python"))

  expected = [{ id: "1", language: "Ruby" }, { id: "2", language: "Python"}].to_json

  assert_equal expected, venue.programmers.to_json
end
