module Ohm

  # Represents a key in Redis.
  class Key < String
    Volatile = new("~")

    def self.[](*args)
      new(args.join(":"))
    end

    def [](key)
      self.class[self, key]
    end

    def volatile
      self.index(Volatile) == 0 ? self : Volatile[self]
    end

    def +(other)
      self.class.new("#{self}+#{other}")
    end

    def -(other)
      self.class.new("#{self}-#{other}")
    end
  end
end
