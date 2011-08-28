module Ohm

  # Represents a key in Redis. Much of the heavylifting is done using the
  # Nest library.
  #
  # The most important change added by {Ohm::Key} to Nest is the concept of
  # volatile keys, which are used heavily when doing {Ohm::Model::Set#find} or
  # {Ohm::Model::Set#except} operations.
  #
  # A volatile key is simply a key prefixed with `~`. This gives you the
  # benefit if quickly seeing which keys are temporary keys by doing something
  # like:
  #
  #     $ redis-cli keys "~*"
  #
  # @see http://github.com/soveran/nest
  class Key < Nest
    def volatile
      self.index("~") == 0 ? self : self.class.new("~", redis)[self]
    end

    # Produces a key with `other` suffixed with itself. This is primarily
    # used for storing SINTERSTORE results.
    def +(other)
      self.class.new("#{self}+#{other}", redis)
    end

    # Produces a key with `other` suffixed with itself. This is primarily
    # used for storing SDIFFSTORE results.
    def -(other)
      self.class.new("#{self}-#{other}", redis)
    end

    # Produces a key with `other` suffixed with itself. This is primarily
    # used for storing SUNIONSTORE results.
    def *(other)
      self.class.new("#{self}_#{other}", redis)
    end
    
    # Return the last (name) component of the key
    def name
      split(':').last
    end
    
    # Produces a random key prefixed with itself.  This is primarily
    # used for storing transient and intermediate results on sets.
    # NB the key name is not guaranteed to be unique, but almost surely so as 1/64**len
    def unique(len=16)
      require 'securerandom'
      self[SecureRandom.urlsafe_base64(len)]
    end
  end
end

