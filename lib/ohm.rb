# encoding: UTF-8

require "base64"
require "redis"
require "nest"

require File.join(File.dirname(__FILE__), "ohm", "pattern")
require File.join(File.dirname(__FILE__), "ohm", "validations")
require File.join(File.dirname(__FILE__), "ohm", "compat-1.8.6")
require File.join(File.dirname(__FILE__), "ohm", "key")

module Ohm

  # Provides access to the _Redis_ database. It is highly recommended that you
  # use this sparingly, and only if you really know what you're doing.
  #
  # The better way to access the _Redis_ database and do raw _Redis_
  # commands would be one of the following:
  #
  # 1. Use {Ohm::Model.key} or {Ohm::Model#key}. So if the name of your
  #    model is *Post*, it would be *Post.key* or the protected method
  #    *#key* which should be used within your *Post* model.
  #
  # 2. Use {Ohm::Model.db} or {Ohm::Model#db}. Although this is also
  #    accessible, it is much cleaner and terse to use {Ohm::Model.key}.
  #
  # @example
  #   class Post < Ohm::Model
  #     def comment_ids
  #       key[:comments].zrange(0, -1)
  #     end
  #
  #     def add_comment_id(id)
  #       key[:comments].zadd(Time.now.to_i, id)
  #     end
  #
  #     def remove_comment_id(id)
  #       # Let's use the db style here just to demonstrate.
  #       db.zrem key[:comments], id
  #     end
  #   end
  #
  #   Post.key[:latest].sadd(1)
  #   Post.key[:latest].smembers == ["1"]
  #   # => true
  #
  #   Post.key[:latest] == "Post:latest"
  #   # => true
  #
  #   p = Post.create
  #   p.comment_ids == []
  #   # => true
  #
  #   p.add_comment_id(101)
  #   p.comment_ids == ["101"]
  #   # => true
  #
  #   p.remove_comment_id(101)
  #   p.comment_ids == []
  #   # => true
  def self.redis
    threaded[:redis] ||= connection(*options)
  end

  # Assign a new _Redis_ connection. Internally used by {Ohm.connect}
  # to clear the cached _Redis_ instance.
  #
  # If you're looking to change the connection or reconnect with different
  # parameters, try {Ohm.connect} or {Ohm::Model.connect}.
  # @see connect
  # @see Model.connect
  # @param connection [Redis] an instance created using `Redis.new`.
  def self.redis=(connection)
    threaded[:redis] = connection
  end

  # @private Used internally by Ohm for thread safety.
  def self.threaded
    Thread.current[:ohm] ||= {}
  end

  # Connect to a _Redis_ database.
  #
  # It is also worth mentioning that you can pass in a *URI* e.g.
  #
  #   Ohm.connect :url => "redis://127.0.0.1:6379/0"
  #
  # Note that the value *0* refers to the database number for the given
  # _Redis_ instance.
  #
  # Also you can use {Ohm.connect} without any arguments. The behavior will
  # be as follows:
  #
  #   # Connect to redis://127.0.0.1:6379/0
  #   Ohm.connect
  #
  #   # Connect to redis://10.0.0.100:22222/5
  #   ENV["REDIS_URL"] = "redis://10.0.0.100:22222/5"
  #   Ohm.connect
  #
  # @param options [{Symbol => #to_s}] An options hash.
  # @see file:OHM_REFERENCE.md#connect_options Ohm.connect options
  #      documentation
  #
  # @example Connect to a database in port 6380.
  #   Ohm.connect(:port => 6380)
  def self.connect(*options)
    self.redis = nil
    @options = options
  end

  # @private Return a connection to Redis.
  #
  # This is a wrapper around Redis.connect(options)
  def self.connection(*options)
    Redis.connect(*options)
  end

  # @private Stores the connection options for Ohm.redis.
  def self.options
    @options = [] unless defined? @options
    @options
  end

  # Clear the database. You typically use this only during testing,
  # or when you seed your site.
  def self.flush
    redis.flushdb
  end

  # The base class of all *Ohm* errors. Can be used as a catch all for
  # Ohm related errors.
  class Error < StandardError; end

  # This is the class that you need to extend in order to define your
  # own models.
  #
  # Probably the most magic happening within {Ohm::Model} is the catching
  # of {Ohm::Model.const_missing} exceptions to allow the use of constants
  # even before they are defined.
  #
  # @example
  #
  #   class Post < Ohm::Model
  #     reference :author, User # no User definition yet!
  #   end
  #
  #   class User < Ohm::Model
  #   end
  #
  # @see Model.const_missing
  class Model

    # Wraps a model name for lazy evaluation.
    class Wrapper < BasicObject

      # Allows you to use a constant even before it is defined. This solves
      # the issue of having to require inter-project dependencies in a very
      # simple and "magic-free" manner.
      #
      # Example of how it was done before Wrapper existed:
      #
      #   require "./app/models/user"
      #   require "./app/models/comment"
      #
      #   class Post < Ohm::Model
      #     reference :author, User
      #     list :comments, Comment
      #   end
      #
      # Now, you can simply do the following:
      #   class Post < Ohm::Model
      #     reference :author, User
      #     list :comments, Comment
      #   end
      #
      # @example
      #   module Commenting
      #     def self.included(base)
      #       base.list :comments, Ohm::Model::Wrapper.new(:Comment) {
      #         Object.const_get(:Comment)
      #       }
      #     end
      #   end
      #
      #   # In your classes:
      #   class Post < Ohm::Model
      #     include Commenting
      #   end
      #
      #   class Comment < Ohm::Model
      #   end
      #
      #   p = Post.create
      #   p.comments.empty?
      #   # => true
      #
      #   p.comments.push(Comment.create)
      #   p.comments.size == 1
      #   # => true
      #
      # @param name [Symbol, String] name of wrapped class.
      # @param block [#to_proc] closure for getting the name of the constant
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

      # Used as a convenience for wrapping an existing constant into an
      # {Ohm::Model::Wrapper}.
      #
      # This is used extensively within the library for points where a user
      # defined class (e.g. _Post_, _User_, _Comment_) is expected.
      #
      # You can also use this if you need to do uncommon things, such as
      # creating your own {Ohm::Model::Set}, {Ohm::Model::List}, etc.
      #
      # (*NOTE:* Keep in mind that the following example is given only as an
      # education example, and is in no way prescribed as good design.)
      #
      #   class User < Ohm::Model
      #   end
      #
      #   User.create(:id => "1001")
      #
      #   Ohm.redis.sadd("myset", 1001)
      #
      #   key = Ohm::Key.new("myset", Ohm.redis)
      #   set = Ohm::Model::Set.new(key, Ohm::Model::Wrapper.wrap(User))
      #
      #   [User[1001]] == set.all.to_a
      #   # => true
      #
      # @see http://ohm.keyvalue.org/tutorials/chaining Chaining Ohm Sets
      def self.wrap(object)
        object.class == self ? object : new(object.inspect) { object }
      end

      # Evaluates the passed block in {Ohm::Model::Wrapper#initialize}.
      #
      # @return [Class] the wrapped class.
      def unwrap
        @block.call
      end

      # Since {Ohm::Model::Wrapper} is a subclass of _BasicObject_ we have
      # to manually declare this.
      #
      # @return [Wrapper]
      def class
        Wrapper
      end

      # @return [String] a string describing this lazy object.
      def inspect
        "<Wrapper for #{@name} (in #{@caller})>"
      end
    end

    # Defines the base implementation for all enumerable types in Ohm,
    # which includes {Ohm::Model::Set}, {Ohm::Model::List} and
    # {Ohm::Model::Index}.
    class Collection
      include Enumerable

      # An instance of {Ohm::Key}.
      attr :key

      # A subclass of {Ohm::Model}
      attr :model

      # @param key [Key] A key which includes a _Redis_ connection.
      # @param model [Ohm::Model::Wrapper] a wrapped subclass of {Ohm::Model}.
      def initialize(key, model)
        @key = key
        @model = model.unwrap
      end

      # Adds an instance of {Ohm::Model} to this collection.
      #
      # @param model [#id] a model with an ID.
      def add(model)
        self << model
      end

      # Sort this collection using the ID by default, or an attribute defined
      # in the elements of this collection.
      #
      # *NOTE:* It is worth mentioning that if you want to sort by a specific
      # attribute instead of an ID, you would probably want to use
      # {Ohm::Model::Collection#sort_by} instead.
      #
      # @example
      #   class Post < Ohm::Model
      #     attribute :title
      #   end
      #
      #   p1 = Post.create(:title => "Alpha")
      #   p2 = Post.create(:title => "Beta")
      #   p3 = Post.create(:title => "Gamma")
      #
      #   [p1, p2, p3] == Post.all.sort.to_a
      #   # => true
      #
      #   [p3, p2, p1] == Post.all.sort(:order => "DESC").to_a
      #   # => true
      #
      #   [p1, p2, p3] == Post.all.sort(:by => "Post:*->title").to_a
      #   # => true
      #
      #   [p3, p2, p1] == Post.all.sort(:by => "Post:*->title",
      #                                 :order => "DESC ALPHA").to_a
      #
      #   # => true
      #
      # @see file:OHM_REFERENCE.md#sort_options Sort options documentation
      # @see http://code.google.com/p/redis/wiki/SortCommand Redis SortCommand
      def sort(_options = {})
        return [] unless key.exists

        options = _options.dup
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
      def sort_by(att, _options = {})
        return [] unless key.exists

        options = _options.dup
        options.merge!(:by => model.key["*->#{att}"])

        if options[:get]
          key.sort(options.merge(:get => model.key["*->#{options[:get]}"]))
        else
          sort(options)
        end
      end

      # Delete this collection.
      #
      # @example
      #
      #   class Post < Ohm::Model
      #     list :comments, Comment
      #   end
      #
      #   class Comment < Ohm::Model
      #   end
      #
      #   post = Post.create
      #   post.comments << Comment.create
      #
      #   post.comments.size == 1
      #   # => true
      #
      #   post.comments.clear
      #   post.comments.size == 0
      #   # => true
      def clear
        key.del
      end

      # Simultaneously clear and add all models. This wraps all operations
      # in a {http://code.google.com/p/redis/wiki/MultiExecCommand MULTI EXEC}
      # block to make the whole operation atomic.
      #
      # @example
      #
      #   class Post < Ohm::Model
      #     list :comments, Comment
      #   end
      #
      #   class Comment < Ohm::Model
      #   end
      #
      #   post = Post.create
      #   post.comments << Comment.create(:id => 100)
      #
      #   post.comments.map(&:id) == ["100"]
      #   # => true
      #
      #   comments = (101..103).to_a.map { |i| Comment.create(:id => i) }
      #
      #   post.comments.replace(comments)
      #   post.comments.map(&:id) == ["101", "102", "103"]
      #   # => true
      def replace(models)
        model.db.multi do
          clear
          models.each { |model| add(model) }
        end
      end

      # @return [true, false] whether or not this collection is empty.
      def empty?
        !key.exists
      end

      # @return [Array] array representation of this collection.
      def to_a
        all
      end
    end

    # Provides a Ruby-esque interface to a _Redis_ *SET*. The *SET* is assumed
    # to be composed of ids which maps to {#model}.
    class Set < Collection
      # An implementation which relies on *SMEMBERS* and yields an instance
      # of {#model}.
      #
      # @see http://code.google.com/p/redis/wiki/SmembersCommand SMEMBERS
      #      in Redis Command Reference.
      def each(&block)
        key.smembers.each { |id| block.call(model[id]) }
      end

      # Convenient way to scope access to a predefined set, useful for access
      # control.
      #
      # @example
      #
      #   class User < Ohm::Model
      #     set :photos, Photo
      #   end
      #
      #   class Photo < Ohm::Model
      #   end
      #
      #   @user = User.create
      #   @user.photos.add(Photo.create(:id => "101"))
      #   @user.photos.add(Photo.create(:id => "102"))
      #
      #   Photo.create(:id => "500")
      #
      #   @user.photos[101] == Photo[101]
      #   # => true
      #
      #   @user.photos[500] == nil
      #   # => true
      #
      # @param [String, Fixnum] id any id existing within this set.
      # @return [Ohm::Model, nil] the model if it exists.
      def [](id)
        model[id] if key.sismember(id)
      end

      # Adds a model to this set.
      #
      # @param [#id] model typically an instance of an {Ohm::Model} subclass.
      #
      # @see http://code.google.com/p/redis/wiki/SaddCommand SADD in Redis
      #      Command Reference.
      def << model
        key.sadd(model.id)
      end

      alias add <<

      # Thin Ruby interface wrapper for *SCARD*.
      #
      # @return [Fixnum] the total number of members for this set.
      # @see http://code.google.com/p/redis/wiki/ScardCommand SCARD in Redis
      #      Command Reference.
      def size
        key.scard
      end

      # Thin Ruby interface wrapper for *SREM*.
      #
      # @param [#id] member a member of this set.
      # @see http://code.google.com/p/redis/wiki/SremCommand SREM in Redis
      #      Command Reference.
      def delete(member)
        key.srem(member.id)
      end

      # Array representation of this set.
      #
      # @example
      #
      #   class Author < Ohm::Model
      #     set :posts, Post
      #   end
      #
      #   class Post < Ohm::Model
      #   end
      #
      #   author = Author.create
      #   author.posts.add(Author.create(:id => "101"))
      #   author.posts.add(Author.create(:id => "102"))
      #
      #   author.posts.all.is_a?(Array)
      #   # => true
      #
      #   author.posts.all.include?(Author[101])
      #   # => true
      #
      #   author.posts.all.include?(Author[102])
      #   # => true
      #
      # @return [Array<Ohm::Model>] all members of this set.
      def all
        key.smembers.map(&model)
      end

      # Allows you to find members of this set which fits the given criteria.
      #
      # @example
      #
      #   class Post < Ohm::Model
      #     attribute :title
      #     attribute :tags
      #
      #     index :title
      #     index :tag
      #
      #     def tag
      #       tags.split(/\s+/)
      #     end
      #   end
      #
      #   post = Post.create(:title => "Ohm", :tags => "ruby ohm redis")
      #   Post.all.is_a?(Ohm::Model::Set)
      #   # => true
      #
      #   Post.all.find(:tag => "ruby").include?(post)
      #   # => true
      #
      #   # Post.find is actually just a wrapper around Post.all.find
      #   Post.find(:tag => "ohm", :title => "Ohm").include?(post)
      #   # => true
      #
      #   Post.find(:tag => ["ruby", "python"]).empty?
      #   # => true
      #
      #   # Alternatively, you may choose to chain them later on.
      #   ruby = Post.find(:tag => "ruby")
      #   ruby.find(:title => "Ohm").include?(post)
      #   # => true
      #
      # @param [Hash] options a hash of key value pairs.
      # @return [Ohm::Model::Set] a set satisfying the filter passed.
      def find(options)
        source = keys(options)
        target = source.inject(key.volatile) { |chain, other| chain + other }
        apply(:sinterstore, key, source, target)
      end

      # Similar to find except that it negates the criteria.
      #
      # @example
      #   class Post < Ohm::Model
      #     attribute :title
      #   end
      #
      #   ohm = Post.create(:title => "Ohm")
      #   ruby = Post.create(:title => "Ruby")
      #
      #   Post.except(:title => "Ohm").include?(ruby)
      #   # => true
      #
      #   Post.except(:title => "Ohm").size == 1
      #   # => true
      #
      # @param [Hash] options a hash of key value pairs.
      # @return [Ohm::Model::Set] a set satisfying the filter passed.
      def except(options)
        source = keys(options)
        target = source.inject(key.volatile) { |chain, other| chain - other }
        apply(:sdiffstore, key, source, target)
      end

      # Returns by default the lowest id value for this set. You may also
      # pass in options similar to {#sort}.
      #
      # @example
      #
      #   class Post < Ohm::Model
      #     attribute :title
      #   end
      #
      #   p1 = Post.create(:id => "101", :title => "Alpha")
      #   p2 = Post.create(:id => "100", :title => "Beta")
      #   p3 = Post.create(:id => "99", :title => "Gamma")
      #
      #   Post.all.is_a?(Ohm::Model::Set)
      #   # => true
      #
      #   p3 == Post.all.first
      #   # => true
      #
      #   p1 == Post.all.first(:order => "DESC")
      #   # => true
      #
      #   p1 == Post.all.first(:by => :title, :order => "ASC ALPHA")
      #   # => true
      #
      #   # just ALPHA also means ASC ALPHA, for brevity.
      #   p1 == Post.all.first(:by => :title, :order => "ALPHA")
      #   # => true
      #
      #   p3 == Post.all.first(:by => :title, :order => "DESC ALPHA")
      #   # => true
      #
      # @param [Hash] options sort options hash.
      # @return [Ohm::Model, nil] an {Ohm::Model} instance or nil if this
      #         set is empty.
      #
      # @see file:OHM_REFERENCE.md#sort_options Sort options documentation
      def first(_options = {})
        options = _options.dup
        options.merge!(:limit => 1)

        if options[:by]
          sort_by(options.delete(:by), options).first
        else
          sort(options).first
        end
      end

      # Ruby-like interface wrapper around *SISMEMBER*.
      #
      # @param [#id] model typically an {Ohm::Model} instance.
      #
      # @return [true, false] whether or not the {Ohm::Model} instance is
      #         a member of this set.
      #
      # @see http://code.google.com/p/redis/wiki/SismemberCommand SISMEMBER
      #      in Redis Command Reference.
      def include?(model)
        key.sismember(model.id)
      end

      def inspect
        "#<Set (#{model}): #{key.smembers.inspect}>"
      end

    protected
      # @private
      def apply(operation, key, source, target)
        target.send(operation, key, *source)
        Set.new(target, Wrapper.wrap(model))
      end

      # @private
      #
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
      # @see Ohm::Model::Set#find
      def find(options)
        keys = keys(options)
        return super(options) if keys.size > 1

        Set.new(keys.first, Wrapper.wrap(model))
      end
    end

    # Provides a Ruby-esque interface to a _Redis_ *LIST*. The *LIST* is
    # assumed to be composed of ids which maps to {#model}.
    class List < Collection
      # An implementation which relies on *LRANGE* and yields an instance
      # of {#model}.
      #
      # @see http://code.google.com/p/redis/wiki/LrangeCommand LRANGE
      #      in Redis Command Reference.
      def each(&block)
        key.lrange(0, -1).each { |id| block.call(model[id]) }
      end

      # Thin wrapper around *RPUSH*.
      #
      # @example
      #
      #   class Post < Ohm::Model
      #     list :comments, Comment
      #   end
      #
      #   class Comment < Ohm::Model
      #   end
      #
      #   p = Post.create
      #   p.comments << Comment.create
      #
      # @param [#id] model typically an {Ohm::Model} instance.
      # @see http://code.google.com/p/redis/wiki/RpushCommand RPUSH
      #      in Redis Command Reference.
      def <<(model)
        key.rpush(model.id)
      end

      alias push <<

      # Returns the element at index, or returns a subarray starting at
      # start and continuing for length elements, or returns a subarray
      # specified by range. Negative indices count backward from the end
      # of the array (-1 is the last element). Returns nil if the index
      # (or starting index) are out of range.
      #
      # @example
      #   class Post < Ohm::Model
      #     list :comments, Comment
      #   end
      #
      #   class Comment < Ohm::Model
      #   end
      #
      #   post = Post.create
      #
      #   10.times { post.comments << Comment.create }
      #
      #   post.comments[0] == Comment[1]
      #   # => true
      #
      #   post.comments[0, 4] == (1..5).map { |i| Comment[i] }
      #   # => true
      #
      #   post.comments[0, 4] == post.comments[0..4]
      #   # => true
      #
      #   post.comments.all == post.comments[0, -1]
      #   # => true
      # @see http://code.google.com/p/redis/wiki/LrangeCommand LRANGE
      #      in Redis Command Reference.
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

      # Convience method for doing list[0], similar to Ruby's Array#first
      # method.
      #
      # @return [Ohm::Model, nil] an {Ohm::Model} instance or nil if the list
      #         is empty.
      def first
        self[0]
      end

      # Returns the model at the tail of this list, while simultaneously
      # removing it from the list.
      #
      # @return [Ohm::Model, nil] an {Ohm::Model} instance or nil if the list
      #         is empty.
      # @see http://code.google.com/p/redis/wiki/LpopCommand RPOP
      #      in Redis Command Reference.
      def pop
        model[key.rpop]
      end

      # Returns the model at the head of this list, while simultaneously
      # removing it from the list.
      #
      # @return [Ohm::Model, nil] an {Ohm::Model} instance or nil if the list
      #         is empty.
      # @see http://code.google.com/p/redis/wiki/LpopCommand LPOP
      #      in Redis Command Reference.
      def shift
        model[key.lpop]
      end

      # Prepends an {Ohm::Model} instance at the beginning of this list.
      #
      # @param [#id] typically an {Ohm::Model} instance.
      #
      # @see http://code.google.com/p/redis/wiki/RpushCommand LPUSH
      #      in Redis Command Reference.
      def unshift(model)
        key.lpush(model.id)
      end

      # Returns an array representation of this list, with elements of the
      # array being an instance of {#model}.
      #
      # @return [Array<Ohm::Model>] instances of {Ohm::Model}.
      def all
        key.lrange(0, -1).map(&model)
      end

      # Thin Ruby interface wrapper for *LLEN*.
      #
      # @return [Fixnum] the total number of elements for this list.
      # @see http://code.google.com/p/redis/wiki/LlenCommand LLEN in Redis
      #      Command Reference.
      def size
        key.llen
      end

      # Ruby-like interface wrapper around *LRANGE*.
      #
      # @param [#id] model typically an {Ohm::Model} instance.
      #
      # @return [true, false] whether or not the {Ohm::Model} instance is
      #         an element of this list.
      #
      # @see http://code.google.com/p/redis/wiki/LrangeCommand LRANGE
      #      in Redis Command Reference.
      def include?(model)
        key.lrange(0, -1).include?(model.id)
      end

      def inspect
        "#<List (#{model}): #{key.lrange(0, -1).inspect}>"
      end
    end

    # All validations which need to access the _Redis_ database goes here.
    # As of this writing, {Ohm::Model::Validations#assert_unique} is the only
    # assertion contained within this module.
    module Validations
      include Ohm::Validations

      # Validates that the attribute or array of attributes are unique. For
      # this, an index of the same kind must exist.
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

    # Raised when you try and get the *id* of an {Ohm::Model} before it is
    # persisted.
    #
    #   class Post < Ohm::Model
    #     list :comments, Comment
    #   end
    #
    #   class Comment < Ohm::Model
    #   end
    #
    #   ex = nil
    #   begin
    #     Post.new.id
    #   rescue Exception => e
    #     ex = e
    #   end
    #
    #   ex.kind_of?(Ohm::Model::MissingID)
    #   # => true
    #
    # This is also one of the most common errors you'll be faced with when
    # you're new to {Ohm} coming from an ActiveRecord background, where you
    # are used to just assigning associations even before the base model is
    # persisted.
    #
    #   # following from the example above:
    #   post = Post.new
    #
    #   ex = nil
    #   begin
    #     post.comments << Comment.new
    #   rescue Exception => e
    #     ex = e
    #   end
    #
    #   ex.kind_of?(Ohm::Model::MissingID)
    #   # => true
    #
    #   # Correct way:
    #   post = Post.new
    #
    #   if post.save
    #     post.comments << Comment.create
    #   end
    class MissingID < Error
      def message
        "You tried to perform an operation that needs the model ID, but it's not present."
      end
    end

    # Raised when you try and do an {Ohm::Model::Set#find} operation and use
    # a key which you did not define as an index.
    #
    #   class Post < Ohm::Model
    #     attribute :title
    #   end
    #
    #   post = Post.create(:title => "Ohm")
    #
    #   ex = nil
    #   begin
    #     Post.find(:title => "Ohm")
    #   rescue Exception => e
    #     ex = e
    #   end
    #
    #   ex.kind_of?(Ohm::Model::IndexNotFound)
    #   # => true
    #
    # To correct this problem, simply define a _:title_ *index* in your class.
    #
    #   class Post < Ohm::Model
    #     attribute :title
    #     index :title
    #   end
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

    def id
      @id or raise MissingID
    end

    # Defines a string attribute for the model. This attribute will be
    # persisted by _Redis_ as a string. Any value stored here will be
    # retrieved in its string representation.
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

    # Defines a counter attribute for the model. This attribute can't be
    # assigned, only incremented or decremented. It will be zero by default.
    #
    # @param name [Symbol] Name of the counter.
    def self.counter(name)
      define_method(name) do
        read_local(name).to_i
      end

      counters << name unless counters.include?(name)
    end

    # Defines a list attribute for the model. It can be accessed only after
    # the model instance is created.
    #
    # @param name [Symbol] Name of the list.
    def self.list(name, model)
      define_memoized_method(name) { List.new(key[name], Wrapper.wrap(model)) }
      collections << name unless collections.include?(name)
    end

    # Defines a set attribute for the model. It can be accessed only after
    # the model instance is created. Sets are recommended when insertion and
    # retreival order is irrelevant, and operations like union, join, and
    # membership checks are important.
    #
    # @param name [Symbol] Name of the set.
    def self.set(name, model)
      define_memoized_method(name) { Set.new(key[name], Wrapper.wrap(model)) }
      collections << name unless collections.include?(name)
    end

    # Creates an index (a set) that will be used for finding instances.
    #
    # If you want to find a model instance by some attribute value, then an
    # index for that attribute must exist.
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
    # @see Ohm::Model.collection
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

    # Define a collection of objects which have a
    # {Ohm::Model.reference reference} to this model.
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
    #   @post = Post.create :content => "Interesting stuff",
    #                       :author => @person
    #   @comment = Comment.create :content => "Indeed!", :post => @post
    #
    #   @post.comments.first.content
    #   # => "Indeed!"
    #
    #   @post.author.name
    #   # => "Albert"
    #
    # *Important*: please note that even though a collection is a
    # {Ohm::Model::Set set},
    # you should not add or remove objects from this collection directly.
    #
    # @see Ohm::Model.reference
    # @param name      [Symbol]   Name of the collection.
    # @param model     [Constant] Model where the reference is defined.
    # @param reference [Symbol]   Reference as defined in the associated
    #                             model.
    def self.collection(name, model, reference = to_reference)
      model = Wrapper.wrap(model)
      define_method(name) { model.unwrap.find(:"#{reference}_id" => send(:id)) }
    end

    # Used by {Ohm::Model.collection} to infer the reference.
    #
    # @return [Symbol] representation of this class in an all-lowercase
    #                  format, separated by underscores and demodulized.
    def self.to_reference
      name.to_s.match(/^(?:.*::)*(.*)$/)[1].gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase.to_sym
    end

    # @private
    def self.define_memoized_method(name, &block)
      define_method(name) do
        @_memo[name] ||= instance_eval(&block)
      end
    end

    # Allows you to find an {Ohm::Model} instance by its *id*.
    #
    # @param  [Fixnum, String]  id the id of the model you want to find.
    # @return [Ohm::Model, nil] the instance of Ohm::Model or nil of it does
    #                           not exist.
    def self.[](id)
      new(:id => id) if id && exists?(id)
    end

    # @private Used for conveniently doing [1, 2].map(&Post) for example.
    def self.to_proc
      Proc.new { |id| self[id] }
    end

    # Returns a {Ohm::Model::Set set} containing all the members of a given
    # class.
    #
    # @example
    #
    #   class Post < Ohm::Model
    #   end
    #
    #   post = Post.create
    #
    #   Post.all.include?(post)
    #   # => true
    #
    #   post.delete
    #
    #   Post.all.include?(post)
    #   # => false
    def self.all
      Ohm::Model::Index.new(key[:all], Wrapper.wrap(self))
    end

    # All the defined attributes within a class.
    # @see Ohm::Model.attribute
    def self.attributes
      @@attributes[self]
    end

    # All the defined counters within a class.
    # @see Ohm::Model.counter
    def self.counters
      @@counters[self]
    end

    # All the defined collections within a class. This will be comprised of
    # all {Ohm::Model::Set sets} and {Ohm::Model::List lists} defined within
    # your class.
    #
    # @example
    #   class Post < Ohm::Model
    #     set  :authors, Author
    #     list :comments, Comment
    #   end
    #
    #   Post.collections == [:authors, :comments]
    #   # => true
    #
    # @see Ohm::Model.list
    # @see Ohm::Model.set
    def self.collections
      @@collections[self]
    end

    # All the defined indices within a class.
    # @see Ohm::Model.index
    def self.indices
      @@indices[self]
    end

    # Convenience method to create and return the newly created object.
    #
    # @example
    #
    #   class Post < Ohm::Model
    #     attribute :title
    #   end
    #
    #   post = Post.create(:title => "A new post")
    #
    # @param  [Hash] args attribute-value pairs for the object.
    # @return [Ohm::Model] an instance of the class you're trying to create.
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
    #   [event1] == Event.find(author: "Albert", day: "2009-09-09").to_a
    #   # => true
    def self.find(hash)
      raise ArgumentError, "You need to supply a hash with filters. If you want to find by ID, use #{self}[id] instead." unless hash.kind_of?(Hash)
      all.find(hash)
    end

    # Encode a value, making it safe to use as a key. Internally used by
    # {Ohm::Model.index_key_for} to canonicalize the indexed values.
    #
    # @param  [#to_s]  value any object you want to be able to use as a key.
    # @return [String] a string which is safe to use as a key.
    # @see Ohm::Model.index_key_for
    def self.encode(value)
      Base64.encode64(value.to_s).gsub("\n", "")
    end

    # Constructor for all subclasses of {Ohm::Model}, which optionally
    # takes a Hash of attribute value pairs.
    #
    # Starting with Ohm 0.1.0, you can use custom ids instead of being forced
    # to use auto incrementing numeric ids, but keep in mind that you have
    # to pass in the preferred id during object initialization.
    #
    # @example
    #
    #   class User < Ohm::Model
    #   end
    #
    #   class Post < Ohm::Model
    #     attribute :title
    #     reference :user, User
    #   end
    #
    #   user = User.create
    #   p1 = Post.new(:title => "Redis", :user_id => user.id)
    #   p1.save
    #
    #   p1.user_id == user.id
    #   # => true
    #
    #   p1.user == user
    #   # => true
    #
    #   # You can also just pass the actual User object, which is the better
    #   # way to do it:
    #   Post.new(:title => "Different way", :user => user).user == user
    #   # => true
    #
    #   # Let's try and generate custom ids
    #   p2 = Post.new(:id => "ohm-redis-library", :title => "Lib")
    #   p2 == Post["ohm-redis-library"]
    #   # => true
    #
    # @param [Hash] attrs attribute value pairs
    def initialize(attrs = {})
      @id = nil
      @_memo = {}
      @_attributes = Hash.new { |hash, key| hash[key] = read_remote(key) }
      update_attributes(attrs)
    end

    # @return [true, false] whether or not this object has an id.
    def new?
      !@id
    end

    # Create this model if it passes all validations.
    #
    # @return [Ohm::Model, nil] the newly created object or nil if it fails
    #                           validation.
    def create
      return unless valid?
      initialize_id

      mutex do
        create_model_membership
        write
        add_to_indices
      end
    end

    # Create or update this object based on the state of #new?.
    #
    # @return [Ohm::Model, nil] the saved object or nil if it fails
    #                           validation.
    def save
      return create if new?
      return unless valid?

      mutex do
        write
        update_indices
      end
    end

    # Update this object, optionally accepting new attributes.
    #
    # @param [Hash] attrs attribute value pairs to use for the updated
    #               version
    # @return [Ohm::Model, nil] the updated object or nil if it fails
    #                           validation.
    def update(attrs)
      update_attributes(attrs)
      save
    end

    # Locally update all attributes without persisting the changes.
    # Internally used by {Ohm::Model#initialize} and {Ohm::Model#update}
    # to set attribute value pairs.
    #
    # @param [Hash] attrs attribute value pairs.
    def update_attributes(attrs)
      attrs.each do |key, value|
        send(:"#{key}=", value)
      end
    end

    # Delete this object from the _Redis_ datastore, ensuring that all
    # indices, attributes, collections, etc are also deleted with it.
    #
    # @return [Ohm::Model] Returns a reference of itself.
    def delete
      delete_from_indices
      delete_attributes(collections) unless collections.empty?
      delete_model_membership
      self
    end

    # Increment the counter denoted by :att.
    #
    # @param [Symbol] att Attribute to increment.
    # @param [Fixnum] count An optional increment step to use.
    def incr(att, count = 1)
      raise ArgumentError, "#{att.inspect} is not a counter." unless counters.include?(att)
      write_local(att, key.hincrby(att, count))
    end

    # Decrement the counter denoted by :att.
    #
    # @param [Symbol] att Attribute to decrement.
    # @param [Fixnum] count An optional decrement step to use.
    def decr(att, count = 1)
      incr(att, -count)
    end

    # Export the id and errors of the object. The `to_hash` takes the opposite
    # approach of providing all the attributes and instead favors a white
    # listed approach.
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

    # Returns the JSON representation of the {#to_hash} for this object.
    # Defining a custom {#to_hash} method will also affect this and return
    # a corresponding JSON representation of whatever you have in your
    # {#to_hash}.
    #
    # @example
    #   require "json"
    #
    #   class Post < Ohm::Model
    #     attribute :title
    #
    #     def to_hash
    #       super.merge(:title => title)
    #     end
    #   end
    #
    #   p1 = Post.create(:title => "Delta Force")
    #   p1.to_hash == { :id => "1", :title => "Delta Force" }
    #   # => true
    #
    #   p1.to_json == "{\"id\":\"1\",\"title\":\"Delta Force\"}"
    #   # => true
    #
    # @return [String] The JSON representation of this object defined in
    #                  terms of {#to_hash}.
    def to_json(*args)
      to_hash.to_json(*args)
    end

    # Convenience wrapper for {Ohm::Model.attributes}.
    def attributes
      self.class.attributes
    end

    # Convenience wrapper for {Ohm::Model.counters}.
    def counters
      self.class.counters
    end

    # Convenience wrapper for {Ohm::Model.collections}.
    def collections
      self.class.collections
    end

    # Convenience wrapper for {Ohm::Model.indices}.
    def indices
      self.class.indices
    end

    # Implementation of equality checking. Equality is defined by two simple
    # rules:
    #
    # 1. They have the same class.
    # 2. They have the same key (_Redis_ key e.g. Post:1 == Post:1).
    #
    # @return [true, false] Whether or not the passed object is equal.
    def ==(other)
      other.kind_of?(self.class) && other.key == key
    rescue MissingID
      false
    end
    alias :eql? :==

    # Allows you to safely use an instance of {Ohm::Model} as a key in a
    # Ruby hash without running into weird scenarios.
    #
    # @example
    #
    #   class Post < Ohm::Model
    #   end
    #
    #   h = {}
    #   p1 = Post.new
    #   h[p1] = "Ruby"
    #   h[p1] == "Ruby"
    #   # => true
    #
    #   p1.save
    #   h[p1] == "Ruby"
    #   # => false
    # @return [Fixnum] An integer representing this object to be used
    #                  as the index for hashes in Ruby.
    def hash
      new? ? super : key.hash
    end

    # Lock the object before executing the block, and release it once the
    # block is done.
    def mutex
      lock!
      yield
      self
    ensure
      unlock!
    end

    # Returns everything, including {Ohm::Model.attributes attributes},
    # {Ohm::Model.collections collections}, {Ohm::Model.counters counters},
    # and the id of this object.
    #
    # Useful for debugging and for doing irb work.
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

    # Makes the model connect to a different Redis instance. This is useful
    # for scaling a large application, where one model can be stored in a
    # different Redis instance, and some other groups of models can be
    # in another Redis instance.
    #
    # This approach of splitting models is a lot simpler than doing a
    # distributed *Redis* solution and may well be the right solution for
    # certain cases.
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
    def self.connect(*options)
      self.db = Ohm.connection(*options)
    end

  protected
    attr_writer :id

    # @return [Ohm::Key] A key scoped to the model which uses this object's
    #                    id.
    #
    # @see http://github.com/soveran/nest The Nest library.
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

    # Wraps any missing constants lazily in {Ohm::Model::Wrapper} delaying
    # the evaluation of constants until they are actually needed.
    #
    # @see http://en.wikipedia.org/wiki/Lazy_evaluation Lazy evaluation
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

    # Allows you to do key manipulations scoped solely to your class.
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

