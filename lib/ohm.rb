# encoding: UTF-8

require "base64"
require "redis"
require "nest"

require File.join(File.dirname(__FILE__), "ohm", "pattern")
require File.join(File.dirname(__FILE__), "ohm", "validations")
require File.join(File.dirname(__FILE__), "ohm", "compat-1.8.6")
require File.join(File.dirname(__FILE__), "ohm", "key")

module Ohm

  # Provides access to the Redis database. This is shared accross all models and instances.
  def self.redis
    threaded[:redis] ||= connection(*options)
  end

  def self.redis=(connection)
    threaded[:redis] = connection
  end

  def self.threaded
    Thread.current[:ohm] ||= {}
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
  def self.connect(*options)
    self.redis = nil
    @options = options
  end

  # Return a connection to Redis.
  #
  # This is a wapper around Redis.connect(options)
  def self.connection(*options)
    Redis.connect(*options)
  end

  def self.options
    @options = [] unless defined? @options
    @options
  end

  # Clear the database.
  def self.flush
    redis.flushdb
  end

  class Error < StandardError; end

  class Model

    # Wraps a model name for lazy evaluation.
    class Wrapper < BasicObject
      def initialize(name, &block)
        @name = name
        @caller = ::Kernel.caller[2]
        @block = block

        class << self
          def method_missing(method_id, *args)
            ::Kernel.raise ::NoMethodError, "You tried to call #{@name}##{method_id}, but #{@name} is not defined on #{@caller}"
          end
        end
      end

      def self.wrap(object)
        object.class == self ? object : new(object.inspect) { object }
      end

      def unwrap
        @block.call
      end

      def class
        Wrapper
      end

      def inspect
        "<Wrapper for #{@name} (in #{@caller})>"
      end
    end

    class Collection
      include Enumerable

      attr :key
      attr :model

      def initialize(key, model)
        @key = key
        @model = model.unwrap
      end

      def add(model)
        self << model
      end

      def first(options = {})
        if options[:by]
          sort_by(options.delete(:by), options.merge(:limit => 1)).first
        else
          model[key.first(options)]
        end
      end

      def [](index)
        model[key[index]]
      end

      def sort(*args)
        key.sort(*args).map(&model)
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
        options.merge!(:by => model.key("*->#{att}"))

        if options[:get]
          key.sort(options.merge(:get => model.key("*->#{options[:get]}")))
        else
          sort(options)
        end
      end

      def clear
        key.del
      end

      def replace(models)
        model.db.multi do
          clear
          models.each { |model| add(model) }
        end
      end

      def empty?
        !key.exists
      end

      def to_a
        all
      end
    end

    class Set < Collection
      def each(&block)
        key.smembers.each { |id| block.call(model[id]) }
      end

      def [](id)
        model[id] if key.sismember(id)
      end

      def << model
        key.sadd(model.id)
      end

      alias add <<

      def size
        key.scard
      end

      def delete(member)
        key.srem(member.id)
      end

      def all
        key.smembers.map(&model)
      end

      def find(options)
        source = keys(options)
        target = source.inject(key.volatile) { |chain, other| chain + other }
        apply(:sinterstore, key, source, target)
      end

      def except(options)
        source = keys(options)
        target = source.inject(key.volatile) { |chain, other| chain - other }
        apply(:sdiffstore, key, source, target)
      end

      def sort(options = {})
        return [] unless key.exists

        options[:start] ||= 0
        options[:limit] = [options[:start], options[:limit]] if options[:limit]

        key.sort(options).map(&model)
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
        return [] unless key.exists

        options.merge!(:by => model.key["*->#{att}"])

        if options[:get]
          key.sort(options.merge(:get => model.key["*->#{options[:get]}"]))
        else
          sort(options)
        end
      end

      def first(options = {})
        options.merge!(:limit => 1)

        if options[:by]
          sort_by(options.delete(:by), options).first
        else
          sort(options).first
        end
      end

      def include?(model)
        key.sismember(model.id)
      end

      def inspect
        "#<Set (#{model}): #{key.smembers.inspect}>"
      end

    protected

      def apply(operation, key, source, target)
        target.send(operation, key, *source)
        Set.new(target, Wrapper.wrap(model))
      end

      # Transform a hash of attribute/values into an array of keys.
      def keys(hash)
        [].tap do |keys|
          hash.each do |key, values|
            values = [values] unless values.kind_of?(Array) # Yes, Array() is different in 1.8.x.
            values.each do |v|
              keys << model.index_key_for(key, v)
            end
          end
        end
      end
    end

    class Index < Set
      def find(options)
        keys = keys(options)
        return super(options) if keys.size > 1

        Set.new(keys.first, Wrapper.wrap(model))
      end
    end

    class List < Collection
      def each(&block)
        key.lrange(0, -1).each { |id| block.call(model[id]) }
      end

      def <<(model)
        key.rpush(model.id)
      end

      alias push <<

      # Returns the element at index, or returns a subarray starting at
      # start and continuing for length elements, or returns a subarray
      # specified by range. Negative indices count backward from the end
      # of the array (-1 is the last element). Returns nil if the index
      # (or starting index) are out of range.
      def [](index, limit = nil)
        case [index, limit]
        when Pattern[Fixnum, Fixnum] then
          key.lrange(index, limit).collect { |id| model[id] }
        when Pattern[Range, nil] then
          key.lrange(index.first, index.last).collect { |id| model[id] }
        when Pattern[Fixnum, nil] then
          model[key.lindex(index)]
        end
      end

      def first
        self[0]
      end

      def pop
        id = key.rpop
        model[id] if id
      end

      def shift
        id = key.lpop
        model[id] if id
      end

      def unshift(model)
        key.lpush(model.id)
      end

      def all
        key.lrange(0, -1).map(&model)
      end

      def size
        key.llen
      end

      def include?(model)
        key.lrange(0, -1).include?(model.id)
      end

      def inspect
        "#<List (#{model}): #{key.lrange(0, -1).inspect}>"
      end
    end

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
        assert result.empty? || !new? && result.include?(id.to_s), [attrs, :not_unique]
      end
    end

    include Validations

    class MissingID < Error
      def message
        "You tried to perform an operation that needs the model ID, but it's not present."
      end
    end

    class IndexNotFound < Error
      def initialize(att)
        @att = att
      end

      def message
        "Index #{@att.inspect} not found."
      end
    end

    @@attributes = Hash.new { |hash, key| hash[key] = [] }
    @@collections = Hash.new { |hash, key| hash[key] = [] }
    @@counters = Hash.new { |hash, key| hash[key] = [] }
    @@indices = Hash.new { |hash, key| hash[key] = [] }

    attr_writer :id

    def id
      @id or raise MissingID
    end

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

      attributes << name unless attributes.include?(name)
    end

    # Defines a counter attribute for the model. This attribute can't be assigned, only incremented
    # or decremented. It will be zero by default.
    #
    # @param name [Symbol] Name of the counter.
    def self.counter(name)
      define_method(name) do
        read_local(name).to_i
      end

      counters << name unless counters.include?(name)
    end

    # Defines a list attribute for the model. It can be accessed only after the model instance
    # is created.
    #
    # @param name [Symbol] Name of the list.
    def self.list(name, model)
      define_memoized_method(name) { List.new(key[name], Wrapper.wrap(model)) }
      collections << name unless collections.include?(name)
    end

    # Defines a set attribute for the model. It can be accessed only after the model instance
    # is created. Sets are recommended when insertion and retrival order is irrelevant, and
    # operations like union, join, and membership checks are important.
    #
    # @param name [Symbol] Name of the set.
    def self.set(name, model)
      define_memoized_method(name) { Set.new(key[name], Wrapper.wrap(model)) }
      collections << name unless collections.include?(name)
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
      indices << att unless indices.include?(att)
    end

    # Define a reference to another object.
    #
    # @example
    #   class Comment < Ohm::Model
    #     attribute :content
    #     reference :post, Post
    #   end
    #
    #   @post = Post.create :content => "Interesting stuff"
    #
    #   @comment = Comment.create(:content => "Indeed!", :post => @post)
    #
    #   @comment.post.content
    #   # => "Interesting stuff"
    #
    #   @comment.post = Post.create(:content => "Wonderful stuff")
    #
    #   @comment.post.content
    #   # => "Wonderful stuff"
    #
    #   @comment.post.update(:content => "Magnific stuff")
    #
    #   @comment.post.content
    #   # => "Magnific stuff"
    #
    #   @comment.post = nil
    #
    #   @comment.post
    #   # => nil
    #
    # @see Ohm::Model::collection
    def self.reference(name, model)
      model = Wrapper.wrap(model)

      reader = :"#{name}_id"
      writer = :"#{name}_id="

      attributes << reader unless attributes.include?(reader)

      index reader

      define_memoized_method(name) do
        model.unwrap[send(reader)]
      end

      define_method(:"#{name}=") do |value|
        @_memo.delete(name)
        send(writer, value ? value.id : nil)
      end

      define_method(reader) do
        read_local(reader)
      end

      define_method(writer) do |value|
        @_memo.delete(name)
        write_local(reader, value)
      end
    end

    # Define a collection of objects which have a {Ohm::Model::reference reference}
    # to this model.
    #
    #   class Comment < Ohm::Model
    #     attribute :content
    #     reference :post, Post
    #   end
    #
    #   class Post < Ohm::Model
    #     attribute  :content
    #     collection :comments, Comment
    #     reference  :author, Person
    #   end
    #
    #   class Person < Ohm::Model
    #     attribute  :name
    #
    #     # When the name of the reference cannot be inferred,
    #     # you need to specify it in the third param.
    #     collection :posts, Post, :author
    #   end
    #
    #   @person = Person.create :name => "Albert"
    #   @post = Post.create :content => "Interesting stuff", :author => @person
    #   @comment = Comment.create :content => "Indeed!", :post => @post
    #
    #   @post.comments.first.content
    #   # => "Indeed!"
    #
    #   @post.author.name
    #   # => "Albert"
    #
    # *Important*: please note that even though a collection is a {Ohm::Set Set},
    # you should not add or remove objects from this collection directly.
    #
    # @see Ohm::Model::reference
    # @param name      [Symbol]   Name of the collection.
    # @param model     [Constant] Model where the reference is defined.
    # @param reference [Symbol]   Reference as defined in the associated model.
    def self.collection(name, model, reference = to_reference)
      model = Wrapper.wrap(model)
      define_method(name) { model.unwrap.find(:"#{reference}_id" => send(:id)) }
    end

    def self.to_reference
      name.to_s.match(/^(?:.*::)*(.*)$/)[1].gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase.to_sym
    end

    def self.define_memoized_method(name, &block)
      define_method(name) do
        @_memo[name] ||= instance_eval(&block)
      end
    end

    def self.[](id)
      new(:id => id) if exists?(id)
    end

    def self.to_proc
      Proc.new { |id| self[id] }
    end

    def self.all
      Ohm::Model::Index.new(key[:all], Wrapper.wrap(self))
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
      raise ArgumentError, "You need to supply a hash with filters. If you want to find by ID, use #{self}[id] instead." unless hash.kind_of?(Hash)
      all.find(hash)
    end

    def self.encode(value)
      Base64.encode64(value.to_s).gsub("\n", "")
    end

    def initialize(attrs = {})
      @id = nil
      @_memo = {}
      @_attributes = Hash.new { |hash, key| hash[key] = read_remote(key) }
      update_attributes(attrs)
    end

    def new?
      !@id
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
      delete_attributes(collections) unless collections.empty?
      delete_model_membership
      self
    end

    # Increment the counter denoted by :att.
    #
    # @param att [Symbol] Attribute to increment.
    def incr(att, count = 1)
      raise ArgumentError, "#{att.inspect} is not a counter." unless counters.include?(att)
      write_local(att, key.hincrby(att, count))
    end

    # Decrement the counter denoted by :att.
    #
    # @param att [Symbol] Attribute to decrement.
    def decr(att, count = 1)
      incr(att, -count)
    end

    # Export the id and errors of the object. The `to_hash` takes the opposite
    # approach of providing all the attributes and instead favors a
    # white listed approach.
    #
    # @example
    #
    #   person = Person.create(:name => "John Doe")
    #   person.to_hash == { :id => '1' }
    #   # => true
    #
    #   # if the person asserts presence of name, the errors will be included
    #   person = Person.create(:name => "John Doe")
    #   person.name = nil
    #   person.valid?
    #   # => false
    #
    #   person.to_hash == { :id => '1', :errors => [[:name, :not_present]] }
    #   # => true
    #
    #   # for cases where you want to provide white listed attributes just do:
    #
    #   class Person < Ohm::Model
    #     def to_hash
    #       super.merge(:name => name)
    #     end
    #   end
    #
    #   # now we have the name when doing a to_hash
    #   person = Person.create(:name => "John Doe")
    #   person.to_hash == { :id => '1', :name => "John Doe" }
    #   # => true
    def to_hash
      attrs = {}
      attrs[:id] = id unless new?
      attrs[:errors] = errors unless errors.empty?
      attrs
    end

    def to_json(*args)
      to_hash.to_json(*args)
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
    alias :eql? :==

    def hash
      new? ? super : key.hash
    end

    # Lock the object before executing the block, and release it once the block is done.
    def mutex
      lock!
      yield
      self
    ensure
      unlock!
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

      "#<#{self.class}:#{new? ? "?" : id} #{everything.map {|e| e.join("=") }.join(" ")}>"
    end

    # Makes the model connect to a different Redis instance.
    #
    # @example
    #
    #   class Post < Ohm::Model
    #     connect :port => 6380, :db => 2
    #
    #     attribute :body
    #   end
    #
    #   # Since these settings are usually environment-specific,
    #   # you may want to call this method from outside of the class
    #   # definition:
    #   Post.connect(:port => 6380, :db => 2)
    #
    def self.connect(*options)
      self.db = Ohm.connection(*options)
    end

  protected

    def key
      self.class.key[id]
    end

    def write
      unless (attributes + counters).empty?
        atts = (attributes + counters).inject([]) { |ret, att|
          value = send(att).to_s

          ret.push(att, value) if not value.empty?
          ret
        }

        db.multi do
          key.del
          key.hmset(*atts.flatten) if atts.any?
        end
      end
    end

    def write_remote(att, value)
      write_local(att, value)

      if value.to_s.empty?
        key.hdel(att)
      else
        key.hset(att, value)
      end
    end

    def self.const_missing(name)
      wrapper = Wrapper.new(name) { const_get(name) }

      # Allow others to hook to const_missing.
      begin
        super(name)
      rescue NameError
      end

      wrapper
    end

  private

    # Provides access to the Redis database. This is shared accross all models and instances.
    def self.db
      Ohm.threaded[self] || Ohm.redis
    end

    def self.db=(connection)
      Ohm.threaded[self] = connection
    end

    def self.key
      Key.new(self, db)
    end

    def self.exists?(id)
      key[:all].sismember(id)
    end

    def initialize_id
      @id ||= self.class.key[:id].incr.to_s
    end

    def db
      self.class.db
    end

    def delete_attributes(atts)
      db.del(*atts.map { |att| key[att] })
    end

    def create_model_membership
      self.class.all << self
    end

    def delete_model_membership
      key.del
      self.class.all.delete(self)
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
      index.sadd(id)
      key[:_indices].sadd(index)
    end

    def delete_from_indices
      key[:_indices].smembers.each do |index|
        db.srem(index, id)
      end

      key[:_indices].del
    end

    def read_local(att)
      @_attributes[att]
    end

    def write_local(att, value)
      @_attributes[att] = value
    end

    def read_remote(att)
      unless new?
        value = key.hget(att)
        value.respond_to?(:force_encoding) ?
          value.force_encoding("UTF-8") :
          value
      end
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
      raise IndexNotFound, att unless indices.include?(att)
      key[att][encode(value)]
    end

    def index_key_for(att, value)
      self.class.index_key_for(att, value)
    end

    # Lock the object so no other instances can modify it.
    # This method implements the design pattern for locks
    # described at: http://code.google.com/p/redis/wiki/SetnxCommand
    #
    # @see Model#mutex
    def lock!
      until key[:_lock].setnx(Time.now.to_f + 0.5)
        next unless timestamp = key[:_lock].get
        sleep(0.1) and next unless lock_expired?(timestamp)

        break unless timestamp = key[:_lock].getset(Time.now.to_f + 0.5)
        break if lock_expired?(timestamp)
      end
    end

    # Release the lock.
    # @see Model#mutex
    def unlock!
      key[:_lock].del
    end

    def lock_expired? timestamp
      timestamp.to_f < Time.now.to_f
    end
  end
end
