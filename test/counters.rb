require_relative "helper"

$VERBOSE = false

class Ad < Ohm::Model
end

test "counters aren't overwritten by competing saves" do
  Ad.counter :hits

  instance1 = Ad.create
  instance1.increment :hits

  instance2 = Ad[instance1.id]

  instance1.increment :hits
  instance1.increment :hits

  instance2.save

  instance1 = Ad[instance1.id]
  assert_equal 3, instance1.hits
end

test "you can increment counters even when attributes is empty" do
  Ad.counter :hits

  ad = Ad.create
  ad = Ad[ad.id]

  ex = nil

  begin
    ad.increment :hits
  rescue ArgumentError => e
    ex = e
  end

  assert_equal nil, ex
end

test "an attribute gets saved properly" do
  Ad.attribute :name
  Ad.counter :hits

  ad = Ad.create(:name => "foo")
  ad.increment :hits, 10
  assert_equal 10, ad.hits

  # Now let's just load and save it.
  ad = Ad[ad.id]
  ad.save

  # The attributes should remain the same
  ad = Ad[ad.id]
  assert_equal "foo", ad.name
  assert_equal 10, ad.hits

  # If we load and save again while we incr behind the scenes,
  # the latest counter values should be respected.
  ad = Ad[ad.id]
  ad.increment :hits, 5
  ad.save

  ad = Ad[ad.id]
  assert_equal 15, ad.hits
end
