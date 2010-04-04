module Ohm
  class Collection
    include Enumerable

    attr_accessor :key, :db

    def initialize(key, db = Ohm.redis)
      self.key = key
      self.db = db
    end

    def each(&block)
      all.each(&block)
    end

    # Return the values as model instances, ordered by the options supplied.
    # Check redis documentation to see what values you can provide to each option.
    #
    # @param options [Hash] options to sort the collection.
    # @option options [#to_s] :by Model attribute to sort the instances by.
    # @option options [#to_s] :order (ASC) Sorting order, which can be ASC or DESC.
    # @option options [Integer] :limit (all) Number of items to return.
    # @option options [Integer] :start (0) An offset from where the limit will be applied.
    #
    # @example Get the first ten users sorted alphabetically by name:
    #
    #   @event.attendees.sort(:by => :name, :order => "ALPHA", :limit => 10)
    #
    # @example Get five posts sorted by number of votes and starting from the number 5 (zero based):
    #
    #   @blog.posts.sort(:by => :votes, :start => 5, :limit => 10")
    def sort(options = {})
      return [] if empty?
      options[:start] ||= 0
      options[:limit] = [options[:start], options[:limit]] if options[:limit]
      db.sort(key, options)
    end

    # Sort the model instances by id and return the first instance
    # found. If a :by option is provided with a valid attribute name, the
    # method sort_by is used instead and the option provided is passed as the
    # first parameter.
    #
    # @see #sort
    # @return [Ohm::Model, nil] Returns the first instance found or nil.
    def first(options = {})
      options = options.merge(:limit => 1)
      sort(options).first
    end

    def [](index)
      first(:start => index)
    end

    def to_ary
      all
    end

    def ==(other)
      to_ary == other
    end

    # @return [true, false] Returns whether or not the collection is empty.
    def empty?
      size.zero?
    end

    # Clears the values in the collection.
    def clear
      db.del(key)
      self
    end

    # Appends the given values to the collection.
    def concat(values)
      values.each { |value| self << value }
      self
    end

    # Replaces the collection with the passed values.
    def replace(values)
      clear
      concat(values)
    end
  end

  # Represents a Redis list.
  #
  # @example Use a list attribute.
  #
  #   class Event < Ohm::Model
  #     attribute :name
  #     list :participants
  #   end
  #
  #   event = Event.create :name => "Redis Meeting"
  #   event.participants << "Albert"
  #   event.participants << "Benoit"
  #   event.participants.all
  #   # => ["Albert", "Benoit"]
  class List < Collection

    # @param value [#to_s] Pushes value to the tail of the list.
    def << value
      db.rpush(key, value)
    end

    alias push <<

    # @return [String] Return and remove the last element of the list.
    def pop
      db.rpop(key)
    end

    # @return [String] Return and remove the first element of the list.
    def shift
      db.lpop(key)
    end

    # @param value [#to_s] Pushes value to the head of the list.
    def unshift(value)
      db.lpush(key, value)
    end

    # @return [Array] Elements of the list.
    def all
      db.lrange(key, 0, -1)
    end

    # @return [Integer] Returns the number of elements in the list.
    def size
      db.llen(key)
    end

    def include?(value)
      all.include?(value)
    end

    def inspect
      "#<List: #{all.inspect}>"
    end
  end

  # Represents a Redis set.
  #
  # @example Use a set attribute.
  #
  #   class Company < Ohm::Model
  #     attribute :name
  #     set :employees
  #   end
  #
  #   company = Company.create :name => "Redis Co."
  #   company.employees << "Albert"
  #   company.employees << "Benoit"
  #   company.employees.all       #=> ["Albert", "Benoit"]
  #   company.employees.include?("Albert")  #=> true
  class Set < Collection

    # @param value [#to_s] Adds value to the list.
    def << value
      db.sadd(key, value)
    end

    def delete(value)
      db.srem(key, value)
    end

    def include?(value)
      db.sismember(key, value)
    end

    def all
      db.smembers(key)
    end

    # @return [Integer] Returns the number of elements in the set.
    def size
      db.scard(key)
    end

    def inspect
      "#<Set: #{all.inspect}>"
    end
  end
end
