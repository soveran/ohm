require "rubygems"
require "redis"

class Model
  @@attributes = Hash.new { |h,k| h[k] = [] }

  attr_accessor :id

  def self.attribute(name)
    attr_accessor(name)
    attributes << name
  end

  def self.[](id)
    if result = $redis[key(self, id)]
      model = new
      model.id = id

      attributes.each do |att|
        model.send("#{att}=", $redis[key(self, id, att)])
      end

      model
    end
  end

  def self.all
    $redis.set_members(key(self)).map do |id|
      self[id]
    end
  end

  def self.attributes
    @@attributes[self]
  end

  def self.next_id
    $redis.incr(key(self, "id"))
  end

  # This check shouldn't be necessary if we add the
  # create method.
  def new?
    ! self.id
  end

  # What about having a create and a save method?
  # The save method would raise an error if the id is nil.
  # The create method would assign an id and then call save.
  def save
    if new?
      self.id = self.class.next_id
      $redis.set_add(self.class.key(self.class), self.id)
      $redis[key] = true
    end

    self.class.attributes.each do |att|
      $redis[key(att)] = send(att)
    end
  end

private

  def key(*args)
    self.class.key([self.class, id] + args)
  end

  def self.key(*args)
    args.join(":")
  end
end
