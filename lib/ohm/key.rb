module Ohm

  # Represents a key in Redis.
  class Key < Nest
    def volatile
      self.index("~") == 0 ? self : self.class.new("~", redis)[self]
    end

    def +(other)
      self.class.new("#{self}+#{other}", redis)
    end

    def -(other)
      self.class.new("#{self}-#{other}", redis)
    end
  end
end
