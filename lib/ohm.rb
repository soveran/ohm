# encoding: UTF-8

require "msgpack"
require "nido"
require "redic"
require "securerandom"
require_relative "ohm/command"

module Ohm
  LUA_CACHE   = Hash.new { |h, k| h[k] = Hash.new }
  LUA_SAVE    = File.expand_path("../ohm/lua/save.lua",   __FILE__)
  LUA_DELETE  = File.expand_path("../ohm/lua/delete.lua", __FILE__)

  # All of the known errors in Ohm can be traced back to one of these
  # exceptions.
  #
  # MissingID:
  #
  #   Comment.new.id # => Error
  #   Comment.new.key # => Error
  #
  #   Solution: you need to save your model first.
  #
  # IndexNotFound:
  #
  #   Comment.find(:foo => "Bar") # => Error
  #
  #   Solution: add an index with `Comment.index :foo`.
  #
  # UniqueIndexViolation:
  #
  #   Raised when trying to save an object with a `unique` index for
  #   which the value already exists.
  #
  #   Solution: rescue `Ohm::UniqueIndexViolation` during save, but
  #   also, do some validations even before attempting to save.
  #
  class Error < StandardError; end
  class MissingID < Error; end
  class IndexNotFound < Error; end
  class UniqueIndexViolation < Error; end

  # Instead of monkey patching Kernel or trying to be clever, it's
  # best to confine all the helper methods in a Utils module.
  module Utils

    # Used by: `attribute`, `counter`, `set`, `reference`,
    # `collection`.
    #
    # Employed as a solution to avoid `NameError` problems when trying
    # to load models referring to other models not yet loaded.
    #
    # Example:
    #
    #   class Comment < Ohm::Model
    #     reference :user, User # NameError undefined constant User.
    #   end
    #
    #   # Instead of relying on some clever `const_missing` hack, we can
    #   # simply use a symbol or a string.
    #
    #   class Comment < Ohm::Model
    #     reference :user, :User
    #     reference :post, "Post"
    #   end
    #
    def self.const(context, name)
      case name
      when Symbol, String
        context.const_get(name)
      else name
      end
    end

    def self.dict(arr)
      Hash[*arr]
    end

    def self.sort(redis, key, options)
      args = []

      args.concat(["BY", options[:by]]) if options[:by]
      args.concat(["GET", options[:get]]) if options[:get]
      args.concat(["LIMIT"] + options[:limit]) if options[:limit]
      args.concat(options[:order].split(" ")) if options[:order]
      args.concat(["STORE", options[:store]]) if options[:store]

      redis.call("SORT", key, *args)
    end
  end

  # Use this if you want to do quick ad hoc redis commands against the
  # defined Ohm connection.
  #
  # Examples:
  #
  #   Ohm.redis.call("SET", "foo", "bar")
  #   Ohm.redis.call("FLUSH")
  #
  def self.redis
    @redis ||= Redic.new
  end

  def self.redis=(redis)
    @redis = redis
  end

  # Wrapper for Ohm.redis.call("FLUSHDB").
  def self.flush
    redis.call("FLUSHDB")
  end

  module Collection
    include Enumerable

    def each
      if block_given?
        ids.each_slice(1000) do |slice|
          fetch(slice).each { |e| yield(e) }
        end
      else
        to_enum
      end
    end

    # Fetch the data from Redis in one go.
    def to_a
      fetch(ids)
    end

    def empty?
      size == 0
    end

    # Wraps the whole pipelining functionality.
    def fetch(ids)
      ids.each do |id|
        redis.queue("HGETALL", namespace[id])
      end

      data = redis.commit

      return [] if data.nil?

      [].tap do |result|
        data.each_with_index do |atts, idx|
          result << model.new(Utils.dict(atts).update(id: ids[idx]))
        end
      end
    end
  end

  class List
    include Collection

    attr :key
    attr :namespace
    attr :model

    def initialize(key, namespace, model)
      @key = key
      @namespace = namespace
      @model = model
    end

    # Returns the total size of the list using LLEN.
    def size
      redis.call("LLEN", key)
    end

    # Returns the first element of the list using LINDEX.
    def first
      model[redis.call("LINDEX", key, 0)]
    end

    # Returns the last element of the list using LINDEX.
    def last
      model[redis.call("LINDEX", key, -1)]
    end

    # Checks if the model is part of this List.
    #
    # An important thing to note is that this method loads all of the
    # elements of the List since there is no command in Redis that
    # allows you to actually check the list contents efficiently.
    #
    # You may want to avoid doing this if your list has say, 10K entries.
    def include?(model)
      ids.include?(model.id)
    end

    # Replace all the existing elements of a list with a different
    # collection of models. This happens atomically in a MULTI-EXEC
    # block.
    #
    # Example:
    #
    #   user = User.create
    #   p1 = Post.create
    #   user.posts.push(p1)
    #
    #   p2, p3 = Post.create, Post.create
    #   user.posts.replace([p2, p3])
    #
    #   user.posts.include?(p1)
    #   # => false
    #
    def replace(models)
      ids = models.map { |model| model.id }

      redis.queue("MULTI")
      redis.queue("DEL", key)
      ids.each { |id| redis.queue("RPUSH", key, id) }
      redis.queue("EXEC")
      redis.commit
    end

    # Pushes the model to the _end_ of the list using RPUSH.
    def push(model)
      redis.call("RPUSH", key, model.id)
    end

    # Pushes the model to the _beginning_ of the list using LPUSH.
    def unshift(model)
      redis.call("LPUSH", key, model.id)
    end

    # Delete a model from the list.
    #
    # Note: If your list contains the model multiple times, this method
    # will delete all instances of that model in one go.
    #
    # Example:
    #
    #   class Comment < Ohm::Model
    #   end
    #
    #   class Post < Ohm::Model
    #     list :comments, :Comment
    #   end
    #
    #   p = Post.create
    #   c = Comment.create
    #
    #   p.comments.push(c)
    #   p.comments.push(c)
    #
    #   p.comments.delete(c)
    #
    #   p.comments.size == 0
    #   # => true
    #
    def delete(model)
      # LREM key 0 <id> means remove all elements matching <id>
      # @see http://redis.io/commands/lrem
      redis.call("LREM", key, 0, model.id)
    end

    # Returns an array with all the ID's of the list.
    #
    #   class Comment < Ohm::Model
    #   end
    #
    #   class Post < Ohm::Model
    #     list :comments, :Comment
    #   end
    #
    #   post = Post.create
    #   post.comments.push(Comment.create)
    #   post.comments.push(Comment.create)
    #   post.comments.push(Comment.create)
    #
    #   post.comments.map(&:id)
    #   # => [1, 2, 3]
    #
    #   post.comments.ids
    #   # => [1, 2, 3]
    #
    def ids
      redis.call("LRANGE", key, 0, -1).map(&:to_i)
    end

  private

    def redis
      model.redis
    end
  end

  # Defines most of the methods used by `Set` and `MultiSet`.
  class BasicSet
    include Collection

    # Allows you to sort by any field in your model.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   User.all.sort_by(:name, :order => "ALPHA")
    #   User.all.sort_by(:name, :order => "ALPHA DESC")
    #   User.all.sort_by(:name, :order => "ALPHA DESC", :limit => [0, 10])
    #
    # Note: This is slower compared to just doing `sort`, specifically
    # because Redis has to read each individual hash in order to sort
    # them.
    #
    def sort_by(att, options = {})
      sort(options.merge(:by => to_key(att)))
    end

    # Allows you to sort your models using their IDs. This is much
    # faster than `sort_by`. If you simply want to get records in
    # ascending or descending order, then this is the best method to
    # do that.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   User.create(:name => "John")
    #   User.create(:name => "Jane")
    #
    #   User.all.sort.map(&:id) == ["1", "2"]
    #   # => true
    #
    #   User.all.sort(:order => "ASC").map(&:id) == ["1", "2"]
    #   # => true
    #
    #   User.all.sort(:order => "DESC").map(&:id) == ["2", "1"]
    #   # => true
    #
    def sort(options = {})
      if options.has_key?(:get)
        options[:get] = to_key(options[:get])
        return execute { |key| Utils.sort(redis, key, options) }
      end

      fetch(execute { |key| Utils.sort(redis, key, options) })
    end

    # Check if a model is included in this set.
    #
    # Example:
    #
    #   u = User.create
    #
    #   User.all.include?(u)
    #   # => true
    #
    # Note: Ohm simply checks that the model's ID is included in the
    # set. It doesn't do any form of type checking.
    #
    def include?(model)
      exists?(model.id)
    end

    # Returns the total size of the set using SCARD.
    def size
      execute { |key| redis.call("SCARD", key) }
    end

    # Syntactic sugar for `sort_by` or `sort` when you only need the
    # first element.
    #
    # Example:
    #
    #   User.all.first ==
    #     User.all.sort(:limit => [0, 1]).first
    #
    #   User.all.first(:by => :name, "ALPHA") ==
    #     User.all.sort_by(:name, :order => "ALPHA", :limit => [0, 1]).first
    #
    def first(options = {})
      opts = options.dup
      opts.merge!(:limit => [0, 1])

      if opts[:by]
        sort_by(opts.delete(:by), opts).first
      else
        sort(opts).first
      end
    end

    # Grab all the elements of this set using SMEMBERS.
    def ids
      execute { |key| redis.call("SMEMBERS", key) }.map(&:to_i)
    end

    # Retrieve a specific element using an ID from this set.
    #
    # Example:
    #
    #   # Let's say we got the ID 1 from a request parameter.
    #   id = 1
    #
    #   # Retrieve the post if it's included in the user's posts.
    #   post = user.posts[id]
    #
    def [](id)
      model[id] if exists?(id)
    end

    # Returns +true+ if +id+ is included in the set. Otherwise, returns +false+.
    #
    # Example:
    #
    #   class Post < Ohm::Model
    #   end
    #
    #   class User < Ohm::Model
    #     set :posts, :Post
    #   end
    #
    #   user = User.create
    #   post = Post.create
    #   user.posts.add(post)
    #
    #   user.posts.exists?('nonexistent') # => false
    #   user.posts.exists?(post.id)       # => true
    #
    def exists?(id)
      execute { |key| redis.call("SISMEMBER", key, id) == 1 }
    end

  private
    def to_key(att)
      if model.counters.include?(att)
        namespace["*:counters->%s" % att]
      else
        namespace["*->%s" % att]
      end
    end
  end

  class Set < BasicSet
    attr :key
    attr :namespace
    attr :model

    def initialize(key, namespace, model)
      @key = key
      @namespace = namespace
      @model = model
    end

    # Chain new fiters on an existing set.
    #
    # Example:
    #
    #   set = User.find(:name => "John")
    #   set.find(:age => 30)
    #
    def find(dict)
      MultiSet.new(
        namespace, model, Command[:sinterstore, key, *model.filters(dict)]
      )
    end

    # Reduce the set using any number of filters.
    #
    # Example:
    #
    #   set = User.find(:name => "John")
    #   set.except(:country => "US")
    #
    #   # You can also do it in one line.
    #   User.find(:name => "John").except(:country => "US")
    #
    def except(dict)
      MultiSet.new(namespace, model, key).except(dict)
    end

    # Do a union to the existing set using any number of filters.
    #
    # Example:
    #
    #   set = User.find(:name => "John")
    #   set.union(:name => "Jane")
    #
    #   # You can also do it in one line.
    #   User.find(:name => "John").union(:name => "Jane")
    #
    def union(dict)
      MultiSet.new(namespace, model, key).union(dict)
    end

  private
    def execute
      yield key
    end

    def redis
      model.redis
    end
  end

  class MutableSet < Set
    # Add a model directly to the set.
    #
    # Example:
    #
    #   user = User.create
    #   post = Post.create
    #
    #   user.posts.add(post)
    #
    def add(model)
      redis.call("SADD", key, model.id)
    end

    alias_method :<<, :add

    # Remove a model directly from the set.
    #
    # Example:
    #
    #   user = User.create
    #   post = Post.create
    #
    #   user.posts.delete(post)
    #
    def delete(model)
      redis.call("SREM", key, model.id)
    end

    # Replace all the existing elements of a set with a different
    # collection of models. This happens atomically in a MULTI-EXEC
    # block.
    #
    # Example:
    #
    #   user = User.create
    #   p1 = Post.create
    #   user.posts.add(p1)
    #
    #   p2, p3 = Post.create, Post.create
    #   user.posts.replace([p2, p3])
    #
    #   user.posts.include?(p1)
    #   # => false
    #
    def replace(models)
      ids = models.map { |model| model.id }

      redis.queue("MULTI")
      redis.queue("DEL", key)
      ids.each { |id| redis.queue("SADD", key, id) }
      redis.queue("EXEC")
      redis.commit
    end
  end

  # Anytime you filter a set with more than one requirement, you
  # internally use a `MultiSet`. `MutiSet` is a bit slower than just
  # a `Set` because it has to `SINTERSTORE` all the keys prior to
  # retrieving the members, size, etc.
  #
  # Example:
  #
  #   User.all.kind_of?(Ohm::Set)
  #   # => true
  #
  #   User.find(:name => "John").kind_of?(Ohm::Set)
  #   # => true
  #
  #   User.find(:name => "John", :age => 30).kind_of?(Ohm::MultiSet)
  #   # => true
  #
  class MultiSet < BasicSet
    attr :namespace
    attr :model
    attr :command

    def initialize(namespace, model, command)
      @namespace = namespace
      @model = model
      @command = command
    end

    # Chain new fiters on an existing set.
    #
    # Example:
    #
    #   set = User.find(:name => "John", :age => 30)
    #   set.find(:status => 'pending')
    #
    def find(dict)
      MultiSet.new(
        namespace, model, Command[:sinterstore, command, intersected(dict)]
      )
    end

    # Reduce the set using any number of filters.
    #
    # Example:
    #
    #   set = User.find(:name => "John")
    #   set.except(:country => "US")
    #
    #   # You can also do it in one line.
    #   User.find(:name => "John").except(:country => "US")
    #
    def except(dict)
      MultiSet.new(
        namespace, model, Command[:sdiffstore, command, unioned(dict)]
      )
    end

    # Do a union to the existing set using any number of filters.
    #
    # Example:
    #
    #   set = User.find(:name => "John")
    #   set.union(:name => "Jane")
    #
    #   # You can also do it in one line.
    #   User.find(:name => "John").union(:name => "Jane")
    #
    def union(dict)
      MultiSet.new(
        namespace, model, Command[:sunionstore, command, intersected(dict)]
      )
    end

  private
    def redis
      model.redis
    end

    def intersected(dict)
      Command[:sinterstore, *model.filters(dict)]
    end

    def unioned(dict)
      Command[:sunionstore, *model.filters(dict)]
    end

    def execute
      # namespace[:tmp] is where all the temp keys should be stored in.
      # redis will be where all the commands are executed against.
      response = command.call(namespace[:tmp], redis)

      begin

        # At this point, we have the final aggregated set, which we yield
        # to the caller. the caller can do all the normal set operations,
        # i.e. SCARD, SMEMBERS, etc.
        yield response

      ensure

        # We have to make sure we clean up the temporary keys to avoid
        # memory leaks and the unintended explosion of memory usage.
        command.clean
      end
    end
  end

  # The base class for all your models. In order to better understand
  # it, here is a semi-realtime explanation of the details involved
  # when creating a User instance.
  #
  # Example:
  #
  #   class User < Ohm::Model
  #     attribute :name
  #     index :name
  #
  #     attribute :email
  #     unique :email
  #
  #     counter :points
  #
  #     set :posts, :Post
  #   end
  #
  #   u = User.create(:name => "John", :email => "foo@bar.com")
  #   u.incr :points
  #   u.posts.add(Post.create)
  #
  # When you execute `User.create(...)`, you run the following Redis
  # commands:
  #
  #   # Generate an ID
  #   INCR User:id
  #
  #   # Add the newly generated ID, (let's assume the ID is 1).
  #   SADD User:all 1
  #
  #   # Store the unique index
  #   HSET User:uniques:email foo@bar.com 1
  #
  #   # Store the name index
  #   SADD User:indices:name:John 1
  #
  #   # Store the HASH
  #   HMSET User:1 name John email foo@bar.com
  #
  # Next we increment points:
  #
  #   HINCR User:1:counters points 1
  #
  # And then we add a Post to the `posts` set.
  # (For brevity, let's assume the Post created has an ID of 1).
  #
  #   SADD User:1:posts 1
  #
  class Model
    def self.redis=(redis)
      @redis = redis
    end

    def self.redis
      defined?(@redis) ? @redis : Ohm.redis
    end

    # Returns the namespace for all the keys generated using this model.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #   end
    #
    #   User.key == "User"
    #   User.key.kind_of?(String)
    #   # => true
    #
    #   User.key.kind_of?(Nido)
    #   # => true
    #
    # To find out more about Nido, see:
    #   http://github.com/soveran/nido
    #
    def self.key
      @key ||= Nido.new(self.name)
    end

    # Retrieve a record by ID.
    #
    # Example:
    #
    #   u = User.create
    #   u == User[u.id]
    #   # =>  true
    #
    def self.[](id)
      new(:id => id).load! if id && exists?(id)
    end

    # Retrieve a set of models given an array of IDs.
    #
    # Example:
    #
    #   ids = [1, 2, 3]
    #   ids.map(&User)
    #
    # Note: The use of this should be a last resort for your actual
    # application runtime, or for simply debugging in your console. If
    # you care about performance, you should pipeline your reads. For
    # more information checkout the implementation of Ohm::List#fetch.
    #
    def self.to_proc
      lambda { |id| self[id] }
    end

    # Check if the ID exists within <Model>:all.
    def self.exists?(id)
      redis.call("SISMEMBER", key[:all], id) == 1
    end

    # Find values in `unique` indices.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     unique :email
    #   end
    #
    #   u = User.create(:email => "foo@bar.com")
    #   u == User.with(:email, "foo@bar.com")
    #   # => true
    #
    def self.with(att, val)
      raise IndexNotFound unless uniques.include?(att)

      id = redis.call("HGET", key[:uniques][att], val)
      new(:id => id).load! if id
    end

    # Find values in indexed fields.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :email
    #
    #     attribute :name
    #     index :name
    #
    #     attribute :status
    #     index :status
    #
    #     index :provider
    #     index :tag
    #
    #     def provider
    #       email[/@(.*?).com/, 1]
    #     end
    #
    #     def tag
    #       ["ruby", "python"]
    #     end
    #   end
    #
    #   u = User.create(name: "John", status: "pending", email: "foo@me.com")
    #   User.find(provider: "me", name: "John", status: "pending").include?(u)
    #   # => true
    #
    #   User.find(:tag => "ruby").include?(u)
    #   # => true
    #
    #   User.find(:tag => "python").include?(u)
    #   # => true
    #
    #   User.find(:tag => ["ruby", "python"]).include?(u)
    #   # => true
    #
    def self.find(dict)
      keys = filters(dict)

      if keys.size == 1
        Ohm::Set.new(keys.first, key, self)
      else
        Ohm::MultiSet.new(key, self, Command.new(:sinterstore, *keys))
      end
    end

    # Retrieve a set of models given an array of IDs.
    #
    # Example:
    #
    #   User.fetch([1, 2, 3])
    #
    def self.fetch(ids)
      all.fetch(ids)
    end

    # Index any method on your model. Once you index a method, you can
    # use it in `find` statements.
    def self.index(attribute)
      indices << attribute unless indices.include?(attribute)
    end

    # Create a unique index for any method on your model. Once you add
    # a unique index, you can use it in `with` statements.
    #
    # Note: if there is a conflict while saving, an
    # `Ohm::UniqueIndexViolation` violation is raised.
    #
    def self.unique(attribute)
      uniques << attribute unless uniques.include?(attribute)
    end

    # Declare an Ohm::Set with the given name.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     set :posts, :Post
    #   end
    #
    #   u = User.create
    #   u.posts.empty?
    #   # => true
    #
    # Note: You can't use the set until you save the model. If you try
    # to do it, you'll receive an Ohm::MissingID error.
    #
    def self.set(name, model)
      track(name)

      define_method name do
        model = Utils.const(self.class, model)

        Ohm::MutableSet.new(key[name], model.key, model)
      end
    end

    # Declare an Ohm::List with the given name.
    #
    # Example:
    #
    #   class Comment < Ohm::Model
    #   end
    #
    #   class Post < Ohm::Model
    #     list :comments, :Comment
    #   end
    #
    #   p = Post.create
    #   p.comments.push(Comment.create)
    #   p.comments.unshift(Comment.create)
    #   p.comments.size == 2
    #   # => true
    #
    # Note: You can't use the list until you save the model. If you try
    # to do it, you'll receive an Ohm::MissingID error.
    #
    def self.list(name, model)
      track(name)

      define_method name do
        model = Utils.const(self.class, model)

        Ohm::List.new(key[name], model.key, model)
      end
    end

    # A macro for defining a method which basically does a find.
    #
    # Example:
    #   class Post < Ohm::Model
    #     reference :user, :User
    #   end
    #
    #   class User < Ohm::Model
    #     collection :posts, :Post
    #   end
    #
    #   # is the same as
    #
    #   class User < Ohm::Model
    #     def posts
    #       Post.find(:user_id => self.id)
    #     end
    #   end
    #
    def self.collection(name, model, reference = to_reference)
      define_method name do
        model = Utils.const(self.class, model)
        model.find(:"#{reference}_id" => id)
      end
    end

    # A macro for defining an attribute, an index, and an accessor
    # for a given model.
    #
    # Example:
    #
    #   class Post < Ohm::Model
    #     reference :user, :User
    #   end
    #
    #   # It's the same as:
    #
    #   class Post < Ohm::Model
    #     attribute :user_id
    #     index :user_id
    #
    #     def user
    #       @_memo[:user] ||= User[user_id]
    #     end
    #
    #     def user=(user)
    #       self.user_id = user.id
    #       @_memo[:user] = user
    #     end
    #
    #     def user_id=(user_id)
    #       @_memo.delete(:user_id)
    #       self.user_id = user_id
    #     end
    #   end
    #
    def self.reference(name, model)
      reader = :"#{name}_id"
      writer = :"#{name}_id="

      attributes << reader unless attributes.include?(reader)

      index reader

      define_method(reader) do
        @attributes[reader]
      end

      define_method(writer) do |value|
        @_memo.delete(name)
        @attributes[reader] = value
      end

      define_method(:"#{name}=") do |value|
        @_memo.delete(name)
        send(writer, value ? value.id : nil)
      end

      define_method(name) do
        @_memo[name] ||= begin
          model = Utils.const(self.class, model)
          model[send(reader)]
        end
      end
    end

    # The bread and butter macro of all models. Basically declares
    # persisted attributes. All attributes are stored on the Redis
    # hash.
    #
    # Example:
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   # It's the same as:
    #
    #   class User < Ohm::Model
    #     def name
    #       @attributes[:name]
    #     end
    #
    #     def name=(name)
    #       @attributes[:name] = name
    #     end
    #   end
    #
    def self.attribute(name, cast = nil)
      attributes << name unless attributes.include?(name)

      if cast
        define_method(name) do
          cast[@attributes[name]]
        end
      else
        define_method(name) do
          @attributes[name]
        end
      end

      define_method(:"#{name}=") do |value|
        @attributes[name] = value
      end
    end

    # Declare a counter. All the counters are internally stored in
    # a different Redis hash, independent from the one that stores
    # the model attributes. Counters are updated with the `incr` and
    # `decr` methods, which interact directly with Redis. Their value
    # can't be assigned as with regular attributes.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     counter :points
    #   end
    #
    #   u = User.create
    #   u.incr :points
    #
    #   u.points
    #   # => 1
    #
    # Note: You can't use counters until you save the model. If you
    # try to do it, you'll receive an Ohm::MissingID error.
    #
    def self.counter(name)
      counters << name unless counters.include?(name)

      define_method(name) do
        return 0 if new?

        redis.call("HGET", key[:counters], name).to_i
      end
    end

    # Keep track of `key[name]` and remove when deleting the object.
    def self.track(name)
      tracked << name unless tracked.include?(name)
    end

    # An Ohm::Set wrapper for Model.key[:all].
    def self.all
      Set.new(key[:all], key, self)
    end

    # Syntactic sugar for Model.new(atts).save
    def self.create(atts = {})
      new(atts).save
    end

    # Returns the namespace for the keys generated using this model.
    # Check `Ohm::Model.key` documentation for more details.
    def key
      model.key[id]
    end

    # Initialize a model using a dictionary of attributes.
    #
    # Example:
    #
    #   u = User.new(:name => "John")
    #
    def initialize(atts = {})
      @attributes = {}
      @_memo = {}
      update_attributes(atts)
    end

    # Access the ID used to store this model. The ID is used together
    # with the name of the class in order to form the Redis key.
    #
    # Example:
    #
    #   class User < Ohm::Model; end
    #
    #   u = User.create
    #   u.id
    #   # => 1
    #
    #   u.key
    #   # => User:1
    #
    def id
      raise MissingID if not defined?(@id)
      @id
    end

    # Check for equality by doing the following assertions:
    #
    # 1. That the passed model is of the same type.
    # 2. That they represent the same Redis key.
    #
    def ==(other)
      other.kind_of?(model) && other.key == key
    rescue MissingID
      false
    end

    # Preload all the attributes of this model from Redis. Used
    # internally by `Model::[]`.
    def load!
      update_attributes(Utils.dict(redis.call("HGETALL", key))) unless new?
      return self
    end

    # Read an attribute remotely from Redis. Useful if you want to get
    # the most recent value of the attribute and not rely on locally
    # cached value.
    #
    # Example:
    #
    #   User.create(:name => "A")
    #
    #   Session 1     |    Session 2
    #   --------------|------------------------
    #   u = User[1]   |    u = User[1]
    #   u.name = "B"  |
    #   u.save        |
    #                 |    u.name == "A"
    #                 |    u.get(:name) == "B"
    #
    def get(att)
      @attributes[att] = redis.call("HGET", key, att)
    end

    # Update an attribute value atomically. The best usecase for this
    # is when you simply want to update one value.
    #
    # Note: This method is dangerous because it doesn't update indices
    # and uniques. Use it wisely. The safe equivalent is `update`.
    #
    def set(att, val)
      if val.to_s.empty?
        redis.call("HDEL", key, att)
      else
        redis.call("HSET", key, att, val)
      end

      @attributes[att] = val
    end

    # Returns +true+ if the model is not persisted. Otherwise, returns +false+.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   u = User.new(:name => "John")
    #   u.new?
    #   # => true
    #
    #   u.save
    #   u.new?
    #   # => false
    def new?
      !defined?(@id)
    end

    # Increment a counter atomically. Internally uses HINCRBY.
    def incr(att, count = 1)
      redis.call("HINCRBY", key[:counters], att, count)
    end

    # Decrement a counter atomically. Internally uses HINCRBY.
    def decr(att, count = 1)
      incr(att, -count)
    end

    # Return a value that allows the use of models as hash keys.
    #
    # Example:
    #
    #   h = {}
    #
    #   u = User.new
    #
    #   h[:u] = u
    #   h[:u] == u
    #   # => true
    #
    def hash
      new? ? super : key.hash
    end
    alias :eql? :==

    # Returns a hash of the attributes with their names as keys
    # and the values of the attributes as values. It doesn't
    # include the ID of the model.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   u = User.create(:name => "John")
    #   u.attributes
    #   # => { :name => "John" }
    #
    def attributes
      @attributes
    end

    # Export the ID of the model. The approach of Ohm is to
    # whitelist public attributes, as opposed to exporting each
    # (possibly sensitive) attribute.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   u = User.create(:name => "John")
    #   u.to_hash
    #   # => { :id => "1" }
    #
    # In order to add additional attributes, you can override `to_hash`:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #
    #     def to_hash
    #       super.merge(:name => name)
    #     end
    #   end
    #
    #   u = User.create(:name => "John")
    #   u.to_hash
    #   # => { :id => "1", :name => "John" }
    #
    def to_hash
      attrs = {}
      attrs[:id] = id unless new?

      return attrs
    end


    # Persist the model attributes and update indices and unique
    # indices. The `counter`s and `set`s are not touched during save.
    #
    # Example:
    #
    #   class User < Ohm::Model
    #     attribute :name
    #   end
    #
    #   u = User.new(:name => "John").save
    #   u.kind_of?(User)
    #   # => true
    #
    def save
      indices = {}
      model.indices.each { |field| indices[field] = Array(send(field)) }

      uniques = {}
      model.uniques.each { |field| uniques[field] = send(field) }

      features = {
        "name" => model.name
      }

      if defined?(@id)
        features["id"] = @id
      end

      response = script(LUA_SAVE, 0,
        features.to_msgpack,
        _sanitized_attributes.to_msgpack,
        indices.to_msgpack,
        uniques.to_msgpack
      )

      if response.is_a?(RuntimeError)
        if response.message =~ /(UniqueIndexViolation: (\w+))/
          raise UniqueIndexViolation, $1
        else
          raise response
        end
      end

      @id = response

      return self
    end

    # Delete the model, including all the following keys:
    #
    # - <Model>:<id>
    # - <Model>:<id>:counters
    # - <Model>:<id>:<set name>
    #
    # If the model has uniques or indices, they're also cleaned up.
    #
    def delete
      uniques = {}
      model.uniques.each { |field| uniques[field] = send(field) }

      script(LUA_DELETE, 0,
        { "name" => model.name,
          "id" => id,
          "key" => key
        }.to_msgpack,
        uniques.to_msgpack,
        model.tracked.to_msgpack
      )

      return self
    end

    # Run lua scripts and cache the sha in order to improve
    # successive calls.
    def script(file, *args)
      cache = LUA_CACHE[redis.url]

      if cache.key?(file)
        sha = cache[file]
      else
        src = File.read(file)
        sha = redis.call("SCRIPT", "LOAD", src)

        cache[file] = sha
      end

      redis.call("EVALSHA", sha, *args)
    end

    # Update the model attributes and call save.
    #
    # Example:
    #
    #   User[1].update(:name => "John")
    #
    #   # It's the same as:
    #
    #   u = User[1]
    #   u.update_attributes(:name => "John")
    #   u.save
    #
    def update(attributes)
      update_attributes(attributes)
      save
    end

    # Write the dictionary of key-value pairs to the model.
    def update_attributes(atts)
      atts.each { |att, val| send(:"#{att}=", val) }
    end

  protected
    def self.to_reference
      name.to_s.
        match(/^(?:.*::)*(.*)$/)[1].
        gsub(/([a-z\d])([A-Z])/, '\1_\2').
        downcase.to_sym
    end

    def self.indices
      @indices ||= []
    end

    def self.uniques
      @uniques ||= []
    end

    def self.counters
      @counters ||= []
    end

    def self.tracked
      @tracked ||= []
    end

    def self.attributes
      @attributes ||= []
    end

    def self.filters(dict)
      unless dict.kind_of?(Hash)
        raise ArgumentError,
          "You need to supply a hash with filters. " +
          "If you want to find by ID, use #{self}[id] instead."
      end

      dict.map { |k, v| to_indices(k, v) }.flatten
    end

    def self.to_indices(att, val)
      raise IndexNotFound unless indices.include?(att)

      if val.kind_of?(Enumerable)
        val.map { |v| key[:indices][att][v] }
      else
        [key[:indices][att][val]]
      end
    end

    attr_writer :id

    def model
      self.class
    end

    def redis
      model.redis
    end

    def _sanitized_attributes
      result = []

      model.attributes.each do |field|
        val = send(field)

        if val
          result.push(field, val.to_s)
        end
      end

      return result
    end
  end
end
