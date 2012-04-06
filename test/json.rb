# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

require "json"
require "ohm/json"

class Venue < Ohm::Model
  attribute :name
  list :programmers, :Programmer

  def validate
    assert_present :name
  end
end

class Programmer < Ohm::Model
  attribute :language

  def validate
    assert_present :language
  end

  def to_hash
    super.merge(:language => language)
  end
end

test "export an empty hash via to_hash" do
  person = Venue.new
  assert Hash.new == person.to_hash
end

test "export a hash with the errors" do
  person = Venue.new
  person.valid?

  assert_equal({ :errors => { :name => [:not_present] }}, person.to_hash)
end

test "export a hash with the its id" do
  person = Venue.create(:name => "John Doe")
  assert Hash[:id => '1'] == person.to_hash
end

test "export a hash with its id and the errors" do
  person = Venue.create(:name => "John Doe")
  person.name = nil
  person.valid?

  expected_hash = { :id => '1', :errors => { :name => [:not_present] }}
  assert expected_hash == person.to_hash
end

test "return the merged attributes" do
  programmer = Programmer.create(:language => "Ruby")
  expected_hash = { :id => '1', :language => 'Ruby' }

  assert expected_hash == programmer.to_hash
end

test "just be the to_hash of a model" do
  json = JSON.parse(Programmer.create(:language => "Ruby").to_json)

  assert ["id", "language"] == json.keys.sort
  assert "1" == json["id"]
  assert "Ruby" == json["language"]
end

test "export an array of records to json" do
  Programmer.create(:language => "Ruby")
  Programmer.create(:language => "Python")

  expected = [{ :id => "1", :language => "Ruby" }, { :id => "2", :language => "Python"}].to_json
  assert_equal expected, Programmer.all.to_json
end

test "export an array of lists to json" do
  venue = Venue.create(:name => "Foo")

  venue.programmers.push(Programmer.create(:language => "Ruby"))
  venue.programmers.push(Programmer.create(:language => "Python"))

  expected = [{ :id => "1", :language => "Ruby" }, { :id => "2", :language => "Python"}].to_json
  assert_equal expected, venue.programmers.to_json
end
