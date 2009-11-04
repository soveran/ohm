# encoding: UTF-8

require "base64"
require File.join(File.dirname(__FILE__), "ohm", "redis")
require File.join(File.dirname(__FILE__), "ohm", "validations")

module Ohm

  # Provides access to the Redis database. This is shared accross all models and instances.
  def redis
    Thread.current[:redis] ||= Ohm::Redis.new(*options)
  end

  def redis=(connection)
    Thread.current[:redis] = connection
  end

  # Connect to a redis database.
  #
  # @param options [Hash] options to create a message with.
  # @option options [#to_s] :host ('127.0.0.1') Host of the redis database.
  # @option options [#to_s] :port (6379) Port number.
  # @option options [#to_s] :db (0) Database number.
  # @option options [#to_s] :timeout (0) Database timeout in seconds.
  # @example Connect to a database in port 6380.
  #   Ohm.connect(:port => 6380)
  def connect(*options)
    self.redis = nil
    @options = options
  end

  def options
    @options
  end

  # Clear the database.
  def flush
    redis.flushdb
  end

  # Join the parameters with ":" to create a key.
  def key(*args)
    args.join(":")
  end

  module_function :key, :connect, :flush, :redis, :redis=, :options

  module Attributes
    class Collection
      include Enumerable

      attr_accessor :key, :db, :model

      def initialize(db, key, model = nil)
        self.db = db
        self.key = key
        self.model = model
      end

      def each(&block)
        all.each(&block)
      end

      # Return instances of model for all the ids contained in the collection.
      def all
        instantiate(raw)
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
        result = db.sort(key, options)
        options[:get] ? result : instantiate(result)
      end

      # Sort the model instances by the given attribute.
      #
      # @example Sorting elements by name:
      #
      #   User.create :name => "B"
      #   User.create :name => "A"
      #
      #   user = User.all.sort_by(:name, :order => "ALPHA").first
      #   user.name == "A"
      #   # => true
      def sort_by(att, options = {})
        sort(options.merge(:by => model.key("*", att)))
      end

      # Sort the model instances by id and return the first instance
      # found. If a :by option is provided with a valid attribute name, the
      # method sort_by is used instead and the option provided is passed as the
      # first parameter.
      #
      # @see #sort
      # @see #sort_by
      # @return [Ohm::Model, nil] Returns the first instance found or nil.
      def first(options = {})
        options = options.merge(:limit => 1)
        options[:by] ?
          sort_by(options.delete(:by), options).first :
          sort(options).first
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

      # @param value [Ohm::Model#id] Adds the id of the object if it's an Ohm::Model.
      def add(model)
        raise ArgumentError unless model.id
        self << model.id
      end

    private

      def instantiate(raw)
        model ? raw.collect { |id| model[id] } : raw
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
    #   event.participants.all #=> ["Albert", "Benoit"]
    class List < Collection

      # @param value [#to_s] Pushes value to the tail of the list.
      def << value
        db.rpush(key, value)
      end

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
      def raw
        db.list(key)
      end

      # @return [Integer] Returns the number of elements in the list.
      def size
        db.llen(key)
      end

      def include?(value)
        raw.include?(value)
      end

      def inspect
        "#<List: #{raw.inspect}>"
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
    #   company.include?("Albert")  #=> true
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

      def raw
        db.smembers(key)
      end

      # @return [Integer] Returns the number of elements in the set.
      def size
        db.scard(key)
      end

      def inspect
        "#<Set: #{raw.inspect}>"
      end
    end

    class Index < Set

      # Returns an intersection with the sets generated from the passed hash.
      #
      # @see Ohm::Model.find
      # @example
      #   @events = Event.find(public: true)
      #
      #   # You can combine the result with sort and other set operations:
      #   @events.sort_by(:name)
      def find(hash)
        apply(:sinterstore, hash, "+")
      end

      # Returns the difference between the receiver and the passed sets.
      #
      # @example
      #   @events = Event.find(public: true).except(status: "sold_out")
      def except(hash)
        apply(:sdiffstore, hash, "-")
      end

      def inspect
        "#<Index: #{raw.inspect}>"
      end

      def clear
        raise Ohm::Model::CannotDeleteIndex
      end

    private

      # Apply a redis operation on a collection of sets.
      def apply(operation, hash, glue)
        indices = keys(hash).unshift(key).uniq
        target = indices.join(glue)
        db.send(operation, target, *indices)
        self.class.new(db, target, model)
      end

      # Transform a hash of attribute/values into an array of keys.
      def keys(hash)
        hash.inject([]) do |acc, t|
          acc + Array(t[1]).map do |v|
            model.index_key_for(t[0], v)
          end
        end
      end
    end
  end

  Error = Class.new(StandardError)

  class Model
    module Validations
      include Ohm::Validations

      # Validates that the attribute or array of attributes are unique. For this,
      # an index of the same kind must exist.
      #
      # @overload assert_unique :name
      #   Validates that the name attribute is unique.
      # @overload assert_unique [:street, :city]
      #   Validates that the :street and :city pair is unique.
      def assert_unique(attrs)
        result = db.sinter(*Array(attrs).map { |att| index_key_for(att, send(att)) })
        assert(result.empty? || result.include?(id.to_s), [attrs, :not_unique])
      end
    end

    include Validations

    class MissingID < Error
      def message
        "You tried to perform an operation that needs the model ID, but it's not present."
      end
    end

    class CannotDeleteIndex < Error
      def message
        "You tried to delete an internal index used by Ohm."
      end
    end

    @@attributes = Hash.new { |hash, key| hash[key] = [] }
    @@collections = Hash.new { |hash, key| hash[key] = [] }
    @@counters = Hash.new { |hash, key| hash[key] = [] }
    @@indices = Hash.new { |hash, key| hash[key] = [] }

    attr_accessor :id

    # Defines a string attribute for the model. This attribute will be persisted by Redis
    # as a string. Any value stored here will be retrieved in its string representation.
    #
    # @param name [Symbol] Name of the attribute.
    def self.attribute(name)
      define_method(name) do
        read_local(name)
      end

      define_method(:"#{name}=") do |value|
        write_local(name, value)
      end

      attributes << name
    end

    # Defines a counter attribute for the model. This attribute can't be assigned, only incremented
    # or decremented. It will be zero by default.
    #
    # @param name [Symbol] Name of the counter.
    def self.counter(name)
      define_method(name) do
        read_local(name).to_i
      end

      counters << name
    end

    # Defines a list attribute for the model. It can be accessed only after the model instance
    # is created.
    #
    # @param name [Symbol] Name of the list.
    def self.list(name, model = nil)
      attr_list_reader(name, model)
      collections << name
    end

    # Defines a set attribute for the model. It can be accessed only after the model instance
    # is created. Sets are recommended when insertion and retrival order is irrelevant, and
    # operations like union, join, and membership checks are important.
    #
    # @param name [Symbol] Name of the set.
    def self.set(name, model = nil)
      attr_set_reader(name, model)
      collections << name
    end

    # Creates an index (a set) that will be used for finding instances.
    #
    # If you want to find a model instance by some attribute value, then an index for that
    # attribute must exist.
    #
    # @example
    #   class User < Ohm::Model
    #     attribute :email
    #     index :email
    #   end
    #
    #   # Now this is possible:
    #   User.find email: "ohm@example.com"
    #
    # @param name [Symbol] Name of the attribute to be indexed.
    def self.index(att)
      indices << att
    end

    def self.attr_list_reader(name, model = nil)
      define_method(name) do
        instance_variable_get("@#{name}") ||
          instance_variable_set("@#{name}", Attributes::List.new(db, key(name), model))
      end
    end

    def self.attr_set_reader(name, model)
      define_method(name) do
        instance_variable_get("@#{name}") ||
          instance_variable_set("@#{name}", Attributes::Set.new(db, key(name), model))
      end
    end

    def self.[](id)
      new(:id => id) if exists?(id)
    end

    def self.to_proc
      Proc.new { |id| self[id] }
    end

    def self.all
      @all ||= Attributes::Index.new(db, key(:all), self)
    end

    def self.attributes
      @@attributes[self]
    end

    def self.counters
      @@counters[self]
    end

    def self.collections
      @@collections[self]
    end

    def self.indices
      @@indices[self]
    end

    def self.create(*args)
      model = new(*args)
      model.create
      model
    end

    # Search across multiple indices and return the intersection of the sets.
    #
    # @example Finds all the user events for the supplied days
    #   event1 = Event.create day: "2009-09-09", author: "Albert"
    #   event2 = Event.create day: "2009-09-09", author: "Benoit"
    #   event3 = Event.create day: "2009-09-10", author: "Albert"
    #
    #   assert_equal [event1], Event.find(author: "Albert", day: "2009-09-09")
    def self.find(hash)
      all.find(hash)
    end

    def self.encode(value)
      Base64.encode64(value.to_s).gsub("\n", "")
    end

    def initialize(attrs = {})
      @_attributes = Hash.new { |hash, key| hash[key] = read_remote(key) }
      update_attributes(attrs)
    end

    def new?
      !id
    end

    def create
      return unless valid?
      initialize_id

      mutex do
        create_model_membership
        write
        add_to_indices
      end
    end

    def save
      return create if new?
      return unless valid?

      mutex do
        write
        update_indices
      end
    end

    def update(attrs)
      update_attributes(attrs)
      save
    end

    def update_attributes(attrs)
      attrs.each do |key, value|
        send(:"#{key}=", value)
      end
    end

    def delete
      delete_from_indices
      delete_attributes(attributes)
      delete_attributes(counters)
      delete_attributes(collections)
      delete_model_membership
      self
    end

    # Increment the counter denoted by :att.
    #
    # @param att [Symbol] Attribute to increment.
    def incr(att)
      raise ArgumentError, "#{att.inspect} is not a counter." unless counters.include?(att)
      write_local(att, db.incr(key(att)))
    end

    # Decrement the counter denoted by :att.
    #
    # @param att [Symbol] Attribute to decrement.
    def decr(att)
      raise ArgumentError, "#{att.inspect} is not a counter." unless counters.include?(att)
      write_local(att, db.decr(key(att)))
    end

    def attributes
      self.class.attributes
    end

    def counters
      self.class.counters
    end

    def collections
      self.class.collections
    end

    def indices
      self.class.indices
    end

    def ==(other)
      other.kind_of?(self.class) && other.key == key
    rescue MissingID
      false
    end

    # Lock the object before ejecuting the block, and release it once the block is done.
    def mutex
      lock!
      yield
      unlock!
      self
    end

    def inspect
      everything = (attributes + collections + counters).map do |att|
        value = begin
                  send(att)
                rescue MissingID
                  nil
                end

        [att, value.inspect]
      end

      "#<#{self.class}:#{id || "?"} #{everything.map {|e| e.join("=") }.join(" ")}>"
    end

  protected

    def key(*args)
      raise MissingID if new?
      self.class.key(id, *args)
    end

    def write
      attributes.each { |att| write_remote(att, send(att)) }
    end

  private

    def self.db
      Ohm.redis
    end

    def self.key(*args)
      Ohm.key(*args.unshift(self))
    end

    def self.exists?(id)
      db.sismember(key(:all), id)
    end

    def initialize_id
      self.id = db.incr(self.class.key("id")).to_s
    end

    def db
      Ohm.redis
    end

    def delete_attributes(atts)
      atts.each do |att|
        db.del(key(att))
      end
    end

    def create_model_membership
      db.sadd(self.class.key(:all), id)
    end

    def delete_model_membership
      db.srem(self.class.key(:all), id)
    end

    def update_indices
      delete_from_indices
      add_to_indices
    end

    def add_to_indices
      indices.each do |att|
        next add_to_index(att) unless collection?(send(att))
        send(att).each { |value| add_to_index(att, value) }
      end
    end

    def collection?(value)
      self.class.collection?(value)
    end

    def self.collection?(value)
      value.kind_of?(Enumerable) &&
      value.kind_of?(String) == false
    end

    def add_to_index(att, value = send(att))
      index = index_key_for(att, value)
      db.sadd(index, id)
      db.sadd(key(:_indices), index)
    end

    def delete_from_indices
      db.smembers(key(:_indices)).each do |index|
        db.srem(index, id)
      end
    end

    def read_local(att)
      @_attributes[att]
    end

    def write_local(att, value)
      @_attributes[att] = value
    end

    def read_remote(att)
      id && db.get(key(att))
    end

    def write_remote(att, value)
      value.nil? ?
        db.del(key(att)) :
        db.set(key(att), value)
    end

    def read_locals(attrs)
      attrs.map do |att|
        send(att)
      end
    end

    def read_remotes(attrs)
      attrs.map do |att|
        read_remote(att)
      end
    end

    def self.index_key_for(att, value)
      raise ArgumentError unless indices.include?(att)
      key(att, encode(value))
    end

    def index_key_for(att, value)
      self.class.index_key_for(att, value)
    end

    # Lock the object so no other instances can modify it.
    # @see Model#mutex
    def lock!
      lock = db.setnx(key(:_lock), 1) until lock == 1
    end

    # Release the lock.
    # @see Model#mutex
    def unlock!
      db.del(key(:_lock))
    end
  end
end
