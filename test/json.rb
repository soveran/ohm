require_relative 'helper'

require "ohm/json"

class Venue < Ohm::Model
  attribute :name
  list :programmers, :Programmer
end

class Programmer < Ohm::Model
  attribute :language

  def to_hash
    super.merge(language: language)
  end
end

test "just be the to_hash of a model" do
  json = JSON.parse(Programmer.create(language: "Ruby").to_json)

  assert ["id", "language"] == json.keys.sort
  assert 1 == json["id"]
  assert "Ruby" == json["language"]
end

test "export an array of records to json" do
  Programmer.create(language: "Ruby")
  Programmer.create(language: "Python")

  expected = [{ id: "1", language: "Ruby" }, { id: "2", language: "Python"}].to_json
  assert_equal expected, Programmer.all.to_json
end

test "export an array of lists to json" do
  venue = Venue.create(name: "Foo")

  venue.programmers.push(Programmer.create(language: "Ruby"))
  venue.programmers.push(Programmer.create(language: "Python"))

  expected = [{ id: "1", language: "Ruby" }, { id: "2", language: "Python"}].to_json
  assert_equal expected, venue.programmers.to_json
end
