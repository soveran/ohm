# encoding: UTF-8

require "base64"
require "redis"
require "nest"

require File.join(File.dirname(__FILE__), "ohm", "compat-1.8.6")
require File.join(File.dirname(__FILE__), "ohm", "helpers")
require File.join(File.dirname(__FILE__), "ohm", "pattern")
require File.join(File.dirname(__FILE__), "ohm", "validations")
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
  #
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
  # @see file:README.html#connecting Ohm.connect options documentation.
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
  #
  # @see http://code.google.com/p/redis/wiki/FlushdbCommand FLUSHDB in the
  #      Redis Command Reference.
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
      #
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
      # @param [Symbol, String] name Canonical name of wrapped class.
      # @param [#to_proc] block Closure for getting the name of the constant.
      def initialize(name, &block)
        @name = name
        @caller = ::Kernel.caller[2]
        @block = block

        class << self
          def method_missing(method_id, *args)
            ::Kernel.raise(
              ::NoMethodError,
              "You tried to call %s#%s, but %s is not defined on %s" % [
                @name, method_id, @name, @caller
              ]
            )
          end
        end
      end

      # Used as a convenience for wrapping an existing constant into a
      # {Ohm::Model::Wrapper wrapper object}.
      #
      # This is used extensively within the library for points where a user
      # defined class (e.g. _Post_, _User_, _Comment_) is expected.
      #
      # You can also use this if you need to do uncommon things, such as
      # creating your own {Ohm::Model::Set Set}, {Ohm::Model::List List}, etc.
      #
      # (*NOTE:* Keep in mind that the following code is given only as an
      # educational example, and is in no way prescribed as good design.)
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
      # @return [Class] The wrapped class.
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

      # @return [String] A string describing this lazy object.
      def inspect
        "<Wrapper for #{@name} (in #{@caller})>"
      end
    end

    # Defines the base implementation for all enumerable types in Ohm,
    # which includes {Ohm::Model::Set Sets}, {Ohm::Model::List Lists} and
    # {Ohm::Model::Index Indices}.
    class Collection
      include Enumerable

      # An instance of {Ohm::Key}.
      attr :key

      # A subclass of {Ohm::Model}.
      attr :model

      # @param [Key] key A key which includes a _Redis_ connection.
      # @param [Ohm::Model::Wrapper] model A wrapped subclass of {Ohm::Model}.
      def initialize(key, model)
        @key = key
        @model = model.unwrap
      end

      # Adds an instance of {Ohm::Model} to this collection.
      #
      # @param [#id] model A model with an ID.
      def add(model)
        self << model
      end

      # Sort this collection using the ID by default, or an attribute defined
      # in the elements of this collection.
      #
      # *NOTE:* It is worth mentioning that if you want to sort by a specific
      # attribute instead of an ID, you would probably want to use
      # {Ohm::Model::Collection#sort_by sort_by} instead.
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
      #   [p1, p2, p3] == Post.all.sort(:by => "Post:*->title",
      #                                 :order => "ASC ALPHA").to_a
      #   # => true
      #
      #   [p3, p2, p1] == Post.all.sort(:by => "Post:*->title",
      #                                 :order => "DESC ALPHA").to_a
      #   # => true
      #
      # @see file:README.html#sorting Sorting in the README.
      # @see http://code.google.com/p/redis/wiki/SortCommand SORT in the
      #      Redis Command Reference.
      def sort(options = {})
        return [] unless key.exists

        opts = options.dup
        opts[:start] ||= 0
        opts[:limit] = [opts[:start], opts[:limit]] if opts[:limit]

        key.sort(opts).map(&model)
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
      #
      # @see file:README.html#sorting Sorting in the README.
      def sort_by(att, options = {})
        return [] unless key.exists

        opts = options.dup
        opts.merge!(:by => model.root.key["*->#{att}"])

        if opts[:get]
          key.sort(opts.merge(:get => model.root.key["*->#{opts[:get]}"]))
        else
          sort(opts)
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
      # @see http://code.google.com/p/redis/wiki/DelCommand DEL in the Redis
      #      Command Reference.
      def clear
        key.del
      end

      # Simultaneously clear and add all models. This wraps all operations
      # in a MULTI EXEC block to make the whole operation atomic.
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
      #
      # @see http://code.google.com/p/redis/wiki/MultiExecCommand MULTI EXEC
      #      in the Redis Command Reference.
      def replace(models)
        model.db.multi do
          clear
          models.each { |model| add(model) }
        end
      end

      # @return [true, false] Whether or not this collection is empty.
      def empty?
        !key.exists
      end

      # @return [Array] Array representation of this collection.
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
      # @example
      #
      #   class Author < Ohm::Model
      #     set :poems, Poem
      #   end
      #
      #   class Poem < Ohm::Model
      #   end
      #
      #   neruda = Author.create
      #   neruda.poems.add(Poem.create)
      #
      #   neruda.poems.each do |poem|
      #     # do something with the poem
      #   end
      #
      #   # if you look at the source, you'll quickly see that this can
      #   # easily be achieved by doing the following:
      #
      #   neruda.poems.key.smembers.each do |id|
      #     poem = Poem[id]
      #     # do something with the poem
      #   end
      #
      # @see http://code.google.com/p/redis/wiki/SmembersCommand SMEMBERS
      #      in Redis Command Reference.
      def each(&block)
        key.smembers.each { |id| block.call(model.to_proc[id]) }
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
      # @param  [#to_s] id Any id existing within this set.
      # @return [Ohm::Model, nil] The model if it exists.
      def [](id)
        model[id] if key.sismember(id)
      end

      # Adds a model or a set of models to this set.
      #
      # @param [#id] model Typically an instance of an {Ohm::Model} subclass of this set,
      #        or a set of models
      #
      # @see http://code.google.com/p/redis/wiki/SaddCommand SADD in Redis
      #      Command Reference.
      def <<(model)
        if model.class <= self.model
          key.sadd(model.id)
        else
          key.sunionstore(key, model.key)
        end
        self
      end
      alias add <<

      # Thin Ruby interface wrapper for *SCARD*.
      #
      # @return [Fixnum] The total number of members for this set.
      # @see http://code.google.com/p/redis/wiki/ScardCommand SCARD in Redis
      #      Command Reference.
      def size
        key.scard
      end

      # Thin Ruby interface wrapper for *SREM*.
      #
      # @param [#id] member a member of this set, or a set of members to be deleted from this set.
      # @see http://code.google.com/p/redis/wiki/SremCommand SREM in Redis
      #      Command Reference.
      def delete(member)
        if member.class <= self.model
          key.srem(member.id)
        else
          key.sdiffstore(key, member.key)
        end
        self
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
      # @return [Array<Ohm::Model>] All members of this set.
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
      # @param  [Hash] options A hash of key value pairs.
      # @return [Ohm::Model::Set] A set satisfying the filter passed.
      def find(options)
        source, target = find_source(options, :+)
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
      # @param  [Hash] options A hash of key value pairs.
      # @return [Ohm::Model::Set] A set satisfying the filter passed.
      def except(options)
        source, target = find_source(options, :-)
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
      # @param  [Hash] options Sort options hash.
      # @return [Ohm::Model, nil] an {Ohm::Model} instance or nil if this
      #         set is empty.
      #
      # @see file:README.html#sorting Sorting in the README.
      def first(options = {})
        opts = options.dup
        opts.merge!(:limit => 1)

        if opts[:by]
          sort_by(opts.delete(:by), opts).first
        else
          sort(opts).first
        end
      end

      # Ruby-like interface wrapper around *SISMEMBER*.
      #
      # @param  [#id] model Typically an {Ohm::Model} instance.
      #
      # @return [true, false] Whether or not the {Ohm::Model model} instance
      #         is a member of this set.
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

      # generate list of source indices and a target volatile index for the find
      # include the subclass index if scoped to a subclass
      #FIXME nil values?  e.g. id: nil
      #TODO pass objects for refs, i.e. find( refd: obj ) as well as find( refd_id: obj.id )
      #TODO union of array of condition hashes
      def find_source(options, op)
        source = keys(options)
        target = source.inject(key.volatile) { |chain, other| chain.send(op, other) }
        model.debug { "find: #{model} #{options}: #{key} #{op} #{source} => #{target}" }
        [source, target]
      end

      # @private
      #
      # Transform a hash of attribute/values into an array of keys.
      #TODO nil values, Set values, ids, refs
      def keys(hash)
#        model.debug { "#{model.name}.find: #{key} : #{hash}" }
        [].tap do |keys|
          hash.each do |attr, values|
            # nb: String is Enumerable in 1.8.x...
            attr_type = model.types[attr]
            if !(Enumerable === values) || ( attr_type && attr_type < Enumerable && attr_type != String )
              Array(values).each do |v|
                keys << model.index_key_for(attr, v)
#                model.debug{"attr: #{attr} v: #{v} key: #{keys.last}"}
              end
            else
              keys << union_key_for(attr,values)
#              model.debug{"attr: #{attr} values: #{values} key: #{keys.last}"}
            end
          end
        end.uniq
      end
      
      def union_key_for(attr, values)
        source = values.map {|v| model.index_key_for(attr, v) }
        target = model.key_for( attr, source.reduce(&:*), :union ).volatile
        model.debug { "union_key_for: #{attr}: #{target} <= #{values}" }
        apply(:sunionstore, source.shift, source, target)
        target
      end
    end

    class Index < Set
      # This method is here primarily as an optimization. Let's say you have
      # the following model:
      #
      #   class Post < Ohm::Model
      #     attribute :title
      #     index :title
      #   end
      #
      #   ruby  = Post.create(:title => "ruby")
      #   redis = Post.create(:title => "redis")
      #
      #   Post.key[:all].smembers == [ruby.id, redis.id]
      #   # => true
      #
      #   Post.index_key_for(:title, "ruby").smembers == [ruby.id]
      #   # => true
      #
      #   Post.index_key_for(:title, "redis").smembers == [redis.id]
      #   # => true
      #
      # If we want to search for example all `Posts` entitled "ruby" or
      # "redis", then it doesn't make sense to do an INTERSECTION with
      # `Post.key[:all]` since it would be redundant, unless we're constrained
      # to a subclass of Post and the index is on a superclass.
      #
      # The implementation of {Ohm::Model::Index#find} avoids this redundancy
      # for the single index case.
      #
      # @see Ohm::Model::Set#find find in Ohm::Model::Set.
      # @see Ohm::Model.find find in Ohm::Model.
      def find(options)
        if key.name == 'all' && options.keys.size == 1 && model.indices(model).include?(options.keys.first) &&
            ( String === options.values.first || !( Enumerable === options.values.first ))
          Set.new(keys(options).first, Wrapper.wrap(model))
        else
          super(options)
        end
      end
    end

    # Provides a Ruby-esque interface to a _Redis_ *LIST*. The *LIST* is
    # assumed to be composed of ids which maps to {#model}.
    class List < Collection
      # An implementation which relies on *LRANGE* and yields an instance
      # of {#model}.
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
      #   post.comments.add(Comment.create)
      #   post.comments.add(Comment.create)
      #
      #   post.comments.each do |comment|
      #     # do something with the comment
      #   end
      #
      #   # reading the source reveals that this is achieved by doing:
      #   post.comments.key.lrange(0, -1).each do |id|
      #     comment = Comment[id]
      #     # do something with the comment
      #   end
      #
      # @see http://code.google.com/p/redis/wiki/LrangeCommand LRANGE
      #      in Redis Command Reference.
      def each(&block)
        key.lrange(0, -1).each { |id| block.call(model.to_proc[id]) }
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
      # @param [#id] model Typically an {Ohm::Model} instance.
      #
      # @see http://code.google.com/p/redis/wiki/RpushCommand RPUSH
      #      in Redis Command Reference.
      def <<(model)
        key.rpush(model.id)
        self
      end
      alias push <<

      # Returns the element at index, or returns a subarray starting at
      # `start` and continuing for `length` elements, or returns a subarray
      # specified by `range`. Negative indices count backward from the end
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
      #
      # @see http://code.google.com/p/redis/wiki/LrangeCommand LRANGE
      #      in Redis Command Reference.
      def [](index, limit = nil)
        case [index, limit]
        when Pattern[Fixnum, Fixnum] then
          key.lrange(index, limit).collect { |id| model.to_proc[id] }
        when Pattern[Range, nil] then
          key.lrange(index.first, index.last).collect { |id| model.to_proc[id] }
        when Pattern[Fixnum, nil] then
          model[key.lindex(index)]
        end
      end

      # Convience method for doing list[0], similar to Ruby's Array#first
      # method.
      #
      # @return [Ohm::Model, nil] An {Ohm::Model} instance or nil if the list
      #         is empty.
      def first
        self[0]
      end

      # Returns the model at the tail of this list, while simultaneously
      # removing it from the list.
      #
      # @return [Ohm::Model, nil] an {Ohm::Model} instance or nil if the list
      #         is empty.
      #
      # @see http://code.google.com/p/redis/wiki/LpopCommand RPOP
      #      in Redis Command Reference.
      def pop
        model[key.rpop]
      end

      # Returns the model at the head of this list, while simultaneously
      # removing it from the list.
      #
      # @return [Ohm::Model, nil] An {Ohm::Model} instance or nil if the list
      #         is empty.
      #
      # @see http://code.google.com/p/redis/wiki/LpopCommand LPOP
      #      in Redis Command Reference.
      def shift
        model[key.lpop]
      end

      # Prepends an {Ohm::Model} instance at the beginning of this list.
      #
      # @param [#id] model Typically an {Ohm::Model} instance.
      #
      # @see http://code.google.com/p/redis/wiki/RpushCommand LPUSH
      #      in Redis Command Reference.
      def unshift(model)
        key.lpush(model.id)
      end

      # Returns an array representation of this list, with elements of the
      # array being an instance of {#model}.
      #
      # @return [Array<Ohm::Model>] Instances of {Ohm::Model}.
      def all
        key.lrange(0, -1).map(&model)
      end

      # Thin Ruby interface wrapper for *LLEN*.
      #
      # @return [Fixnum] The total number of elements for this list.
      #
      # @see http://code.google.com/p/redis/wiki/LlenCommand LLEN in Redis
      #      Command Reference.
      def size
        key.llen
      end

      # Ruby-like interface wrapper around *LRANGE*.
      #
      # @param [#id] model Typically an {Ohm::Model} instance.
      #
      # @return [true, false] Whether or not the {Ohm::Model} instance is
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
      def assert_unique(atts, error = [atts, :not_unique])
        indices = Array(atts).map { |att| index_key_for(att, send(att)) }
        result  = db.sinter(*indices)

        assert result.empty? || !new? && result == Array(id.to_s), error
      end
    end

    include Validations

    # Raised when you try and get the *id* of an {Ohm::Model} without an id.
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
        "You tried to perform an operation that needs the model ID, " +
        "but it's not present."
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

    @@attributes  = Hash.new { |hash, key| hash[key] = [] }
    @@collections = Hash.new { |hash, key| hash[key] = [] }
    @@counters    = Hash.new { |hash, key| hash[key] = [] }
    @@indices     = Hash.new { |hash, key| hash[key] = [] }
    @@types       = Hash.new { |hash, key| hash[key] = {} }
    @@serializers = Hash.new { |hash, key| hash[key] = {} }

    def id
      @id or raise MissingID
    end

    def changed?
      @changed
    end

    # shortcut for reading an attribute value of the model
    def [](attr)
      send(attr)
    end
    
    # shortcut for writing an attribute value
    def []=(attr, val)
      send(:"#{attr}=", val)
    end

    # Defines a string attribute for the model. This attribute will be
    # persisted by _Redis_ as a string. Any value stored here will be
    # retrieved in its string representation.
    #
    # If you're looking to have typecasting built in, you may want to look at
    # Ohm::Typecast in Ohm::Contrib.
    #
    # @param name [Symbol] Name of the attribute.
    # @see http://cyx.github.com/ohm-contrib/doc/Ohm/Typecast.html
    def self.attribute(name)
      define_method(name) do
        read_local(name)
      end

      define_method(:"#{name}=") do |value|
        write_local(name, value)
      end

      attributes(self) << name unless attributes.include?(name)
    end

    # Defines a counter attribute for the model. This attribute can't be
    # assigned, only incremented or decremented. It will be zero by default.
    #
    # @param [Symbol] name Name of the counter.
    def self.counter(name)
      define_method(name) do
        read_local(name).to_i
      end

      counters(self) << name unless counters.include?(name)
    end

    # Defines a list attribute for the model. It can be accessed only after
    # the model instance is created, or if you assign an :id during object
    # construction.
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
    #   # WRONG!!!
    #   post = Post.new
    #   post.comments << Comment.create
    #
    #   # Right :-)
    #   post = Post.create
    #   post.comments << Comment.create
    #
    #   # Alternative way if you want to have custom ids.
    #   post = Post.new(:id => "my-id")
    #   post.comments << Comment.create
    #   post.create
    #
    # @param [Symbol] name Name of the list.
    def self.list(name, model)
      define_memoized_method(name) { List.new(key[name], Wrapper.wrap(model)) }
      define_method(:"#{name}=") { |value| send(name).replace(value) }
      collections(self) << name unless collections.include?(name)
    end

    # Defines a set attribute for the model. It can be accessed only after
    # the model instance is created. Sets are recommended when insertion and
    # retreival order is irrelevant, and operations like union, join, and
    # membership checks are important.
    #
    # @param [Symbol] name Name of the set.
    def self.set(name, model)
      define_memoized_method(name) { Set.new(key[name], Wrapper.wrap(model)) }
      define_method(:"#{name}=") { |value| send(name).replace(value) }
      collections(self) << name unless collections.include?(name)
    end

    # Creates an index (a set) that will be used for finding instances.
    #
    # If you want to find a model instance by some attribute value, then an
    # index for that attribute must exist.
    #
    # @example
    #
    #   class User < Ohm::Model
    #     attribute :email
    #     index :email
    #   end
    #
    #   # Now this is possible:
    #   User.find :email => "ohm@example.com"
    #
    # @param [Symbol] name Name of the attribute to be indexed.
    def self.index(att)
      indices(self) << att unless indices.include?(att)
    end

    # Define a reference to another object.
    #
    # @example
    #
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
    # @see file:README.html#references References Explained.
    # @see Ohm::Model.collection
    def self.reference(name, model, options={})
      model = Wrapper.wrap(model)
      
      reader = :"#{name}_id"
      writer = :"#{name}_id="
      fkey = options.via || :id

      attributes(self) << reader unless attributes.include?(reader)

      index reader

      define_memoized_method(name) do
        model.unwrap[send(reader)]
      end

      define_method(:"#{name}=") do |value|
        @_memo.delete(name)
        send(writer, value ? value.send(fkey) : nil)
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
    # *Important*: Please note that even though a collection is a
    # {Ohm::Model::Set set}, you should not add or remove objects from this
    # collection directly.
    #
    # @see Ohm::Model.reference
    # @param name      [Symbol]   Name of the collection.
    # @param model     [Constant] Model where the reference is defined.
    # @param reference [Symbol]   Reference as defined in the associated
    #                             model.
    #
    # @see file:README.html#collections Collections Explained.
    def self.collection(name, model, reference = to_reference)
      model = Wrapper.wrap(model)
      define_method(name) {
        model.unwrap.find(:"#{reference}_id" => send(:id))
      }
      collections(self) << name unless collections.include?(name)
    end

    # Used by {Ohm::Model.collection} to infer the reference.
    #
    # @return [Symbol] Representation of this class in an all-lowercase
    #                  format, separated by underscores and demodulized.
    def self.to_reference
      name.to_s.
        match(/^(?:.*::)*(.*)$/)[1].
        gsub(/([a-z\d])([A-Z])/, '\1_\2').
        downcase.to_sym
    end

    # @private
    def self.define_memoized_method(name, &block)
      define_method(name) do
        @_memo[name] ||= instance_eval(&block)
      end
    end

    # Allows you to find an {Ohm::Model} instance by its *id*.
    #
    # @param  [#to_s] id The id of the model you want to find.
    # @return [Ohm::Model, nil] The instance of Ohm::Model or nil of it does
    #                           not exist.
    def self.[](id)
      new(:id => id) if id && root.exists?(id)
    end

    # @private Used for conveniently doing [1, 2].map(&Post) for example.
    def self.to_proc
      lambda { |id| new(:id => id) }
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

    # Return an empty {Ohm::Model::Set set}
    def self.none
      Ohm::Model::Index.new(key.volatile.unique, Wrapper.wrap(self))
    end

    # All the defined attributes within a class.
    # @see Ohm::Model.attribute
    def self.attributes(klass=nil)
      klass ? @@attributes[klass] : all_ancestors(@@attributes)
    end

    # Map of the types of defined attributes within a class.
    # @see Ohm::Model.attribute
    def self.types(klass=nil)
      klass ? @@types[klass] : @@types[root].merge(@@types[base])
    end

    # Map of the attribute serializers within a class
    def self.serializers(klass=root)
      klass ? @@serializers[klass] : @@serializers
    end
      
    # All the defined counters within a class.
    # @see Ohm::Model.counter
    def self.counters(klass=nil)
      klass ? @@counters[klass] : all_ancestors(@@counters)
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
    def self.collections(klass=nil)
      klass ? @@collections[klass] : all_ancestors(@@collections)
    end

    # All the defined indices within a class.
    # @see Ohm::Model.index
    def self.indices(klass=nil)
      klass ? @@indices[klass] : all_ancestors(@@indices)
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
    def self.create(*args, &block)
      args.unshift(self) if Hash === args.first && args.first.key?(:id)
      model = new(*args, &block)
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
      unless hash.kind_of?(Hash)
        raise ArgumentError,
          "You need to supply a hash with filters. " +
          "If you want to find by ID, use #{self}[id] instead."
      end

      all.find(hash)
    end

    # Encode a value, making it safe to use as a key. Internally used by
    # {Ohm::Model.index_key_for} to canonicalize the indexed values.
    #
    # @param  [#to_s]  value Any object you want to be able to use as a key.
    # @return [String] A string which is safe to use as a key.
    # @see Ohm::Model.index_key_for
    def self.encode(value)
      Base64.strict_encode64(digest(value.to_s))
    end
    
    # Optionally digest a long key name with a hash function if the key is longer than the hash
    def self.digest(value)
      value
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
    # @param [Hash] attrs Attribute value pairs.
    def initialize(attrs = {})
      @id = nil
      @_memo ||= {}
      @_attributes ||= Hash.new { |hash, key| hash[key] = lazy_fetch(key) }
      update_local(attrs)
    end

    # Instantiate a new instance of a model, or if given an id of an existing model,
    # instantiate it or possibly a subclass according to its _type attribute if it
    # exists in the datastore. (I.e. polymorphic creation of the return instance.)
    #
    # Optionally takes a Class name as its first arg to override the dynamic typing
    # and coerce the existing model to the given type.
    #
    # @example
    #
    #  static: return a new Cat
    #    Cat.new( name: 'fluffy' )
    #
    #  polymorphic: retrieve whatever type of animal has id 3, set name
    #    Animal.new( id: 3, name: 'pidgin' )
    #
    #  dynamic coercion: morph whatever type of animal has id 3 into a new Cat, set name
    #    Animal.new( Cat, id: 3, name: 'chimera' )
    #
    def self.new(*args, &block)
      attrs = args.extract_options!

      type =  args.shift || attrs[:id] && self.polymorphic && read_remote(root.key[attrs[:id]], :_type)
      klass = constantize( type.to_s ) if type

      instance = 
        if klass && klass < self
          klass.new( klass, attrs )
        elsif !klass || klass == self
          super( attrs )
        else
          nil
        end

      if instance
        instance.instance_variable_set(:@_type, klass)
        yield instance if block_given?
      end
      instance
    end
    
    # @return [true, false] Whether or not this object has an id.
    def new?
      !@id
    end

    # Create this model if it passes all validations.
    #
    # @return [Ohm::Model, nil] The newly created object or nil if it fails
    #                           validation.
    def create
      return false unless valid?
      _create
    end
    
    # Create or update this object based on the state of #new?.
    #
    # @return [Ohm::Model, nil] The saved object or nil if it fails
    #                           validation.
    def save
      return create if new?
      return false unless valid?
      _save
    end
    
    # Update this object, optionally accepting new attributes.
    #
    # @param [Hash] attrs Attribute value pairs to use for the updated
    #               version
    # @return [Ohm::Model, nil] The updated object or nil if it fails
    #                           validation.
    def update(attrs)
      update_local(attrs)
      save
    end
    alias_method :update_attributes, :update
    
    # Locally update all attributes without persisting the changes.
    # Internally used by {Ohm::Model#initialize} and {Ohm::Model#update}
    # to set attribute value pairs.
    #
    # @param [Hash] attrs Attribute value pairs.
    def update_local(attrs)
      attrs.each do |key, value|
        send(:"#{key}=", value)
      end
      self
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
    alias_method :destroy, :delete
    
    # Increment the counter denoted by :att.
    #
    # @param [Symbol] att Attribute to increment.
    # @param [Fixnum] count An optional increment step to use.
    def incr(att, count = 1)
      unless counters.include?(att)
        raise ArgumentError, "#{att.inspect} is not a counter."
      end

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
    # options hash may be passed for use by subclasses (e.g., filte parameters)
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
    def to_hash(*options)
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
    #
    # @return [Fixnum] An integer representing this object to be used
    #                  as the index for hashes in Ruby.
    def hash
      new? ? super : key.hash
    end

    # Lock the object before executing the block, and release it once the
    # block is done.
    #
    # This is used during {#create} and {#save} to ensure that no race
    # conditions occur.
    #
    # @see http://code.google.com/p/redis/wiki/SetnxCommand SETNX in the
    #      Redis Command Reference.
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
      everything = attributes_for_inspect.map do |att|
        value = begin
                  send(att)
                rescue MissingID
                  nil
                end

        [att, value.inspect]
      end

      sprintf("#<%s:%s %s>",
              self.class,
              new? ? "?" : id,
              everything.map {|e| e.join("=") }.join(" ")
      )
    end

    if !defined?(debug)
      def self.debug(*msg, &block)
         logger.debug( Array(msg).first || yield ) if logger && log_level == Logger::DEBUG
      end

      def debug(*msg, &block); self.class.debug(*msg, &block); end
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
    #
    # @see file:README.html#connecting Ohm.connect options documentation.
    def self.connect(*options)
      self.db = Ohm.connection(*options)
    end

    # @return [Ohm::Key] A key scoped to the model root which uses this object's
    #                    id.
    #
    # @see http://github.com/soveran/nest The Nest library.
    def key
      root.key[id]
    end

    def root
      self.class.root
    end
    
    def self.root
      @root ||= ( !(base == superclass || base == self) && superclass.respond_to?(:root) ) ? superclass.root : self
    end

    def self.polymorphic(p=nil)
      #TODO this is a problem if not all the descendants are yet loaded/autoloaded
      # the subclasses must be seen in order for the root to be considered polymorphic
      # and the _type fetching optimization in new() to be short circuited
      # If it's not convenient to preload the subclasses then just declare the root
      # class explicitly polymorphic(true) so that subclasses can be autoloaded
      #TODO make this automatic by keeping a set of the polymorphs in the db
      # i.e. root[:_types].smembers
      @_polymorph ||= self < root || ( self == root && !polymorphs.empty? ) || p
    end

    # all the derived models, if any
    def self.polymorphs
      @_descendants ||= descendants.select{|klass| klass < Ohm::Model }
    end
    
  protected

    # Return the list of attributes, collections, counters etc. for inspect
    def attributes_for_inspect
      (attributes + collections + counters)
    end
    
    attr :_type
    attr_writer :id

    def changed!
      @changed = true
    end

    # internal create action
    def _create
      initialize_id if new?
        
      mutex do
        create_model_membership
        write
        add_to_indices
      end
    end

    # internal save action
    def _save
      mutex do
        create_model_membership
        write
        update_indices
      end
    end


    # Write all the attributes and counters of this object. The operation
    # is actually a 2-step process:
    #
    # 1. Delete the current key, e.g. Post:2.
    # 2. Set all of the new attributes (using HMSET).
    #
    # The DEL and HMSET operations are wrapped in a MULTI EXEC block to ensure
    # the atomicity of the write operation.
    #
    # @see http://code.google.com/p/redis/wiki/DelCommand DEL in the
    #      Redis Command Reference.
    # @see http://code.google.com/p/redis/wiki/HmsetCommand HMSET in the
    #      Redis Command Reference.
    # @see http://code.google.com/p/redis/wiki/MultiExecCommand MULTI EXEC
    #      in the Redis Command Reference.
    def write
      unless (attributes + counters).empty?
        atts = (attributes + counters).inject([]) { |ret, att|
          value = serialize(att)

          ret.push(att, value) if not value.empty?
          ret
        }
        atts.unshift([:_type, self.class.name]) if self.class != root
        write_remotes(atts)
      end
      @changed = false
    end
    
    # Get and serialize the attribute value for att for writing to the database
    # This is a hook used e.g. by Serialized 
    def serialize(att, val=send(att))
      val.to_s
    end

    # persist a list of attribute/values remotely
    # atts is an array of [ a1, v1, a2, v2... ] or an attributes hash
    def write_remotes( atts = nil )
      atts ||= @_attributes
      db.multi do
        key.del
        key.hmset(*atts.flatten) if atts.any?
      end
    end

    # Write a single attribute both locally and remotely. It's very important
    # to know that this method skips validation checks, therefore you must
    # ensure data integrity and validity in your application code.
    #
    # @param [Symbol, String] att The name of the attribute to write.
    # @param [#to_s] value The value of the attribute to write.
    #
    # @see http://code.google.com/p/redis/wiki/HdelCommand HDEL in the
    #      Redis Command Reference.
    # @see http://code.google.com/p/redis/wiki/HsetCommand HSET in the
    #      Redis Command Reference.
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
    # @see Ohm::Model::Wrapper
    # @see http://en.wikipedia.org/wiki/Lazy_evaluation Lazy evaluation
    def self.const_missing(name)
      wrapper = Wrapper.new(name) { const_get(name) }

      # Allow others to hook to const_missing.
      begin
        super(name)
      rescue NameError
        wrapper
      end

    end

  private

    # roll up all the attribute names from self and all superclasses
    def self.all_ancestors(attr)
      model_ancestors.map { |klass| attr[klass] }.flatten
    end
    
    # cache model ancestors
    def self.model_ancestors
      @_model_ancestors ||= begin
        a = ancestors
        a[0..a.index(base)].select{|k| k.respond_to? :model_ancestors }
      end
    end
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

    # The meat of the ID generation code for Ohm. For cases where you want to
    # customize ID generation (i.e. use GUIDs or Base62 ids) then you simply
    # override this method in your model.
    #
    # @example
    #
    #   module UUID
    #     def self.new
    #       `uuidgen`.strip
    #     end
    #   end
    #
    #   class Post < Ohm::Model
    #
    #   private
    #     def initialize_id
    #       @id ||= UUID.new
    #     end
    #   end
    #
    def initialize_id
      @id ||= root.key[:id].incr.to_s
    end
    
    def db
      self.class.db
    end

    # base is the superclass of root. Normally this is Ohm::Model in which case all user models
    # that inherit from Ohm::Model will have their own roots.
    #
    # @example
    #
    #   class MyModel::Base < Ohm::Model
    #     self.base = self
    #   end
    #
    #   class User < MyModel::Base; end
    #   u = User.create
    #   u = User.find(...)  # User is the root, not MyModel::Base
    #
    class << self
      attr_accessor :base, :logger, :log_level
      silence_warnings do
        def base
          @base ||= self
        end
        
        def logger
          @logger ||= nil || superclass.logger rescue nil
        end

        def log_level
          @log_level ||= nil || superclass.log_level rescue nil
        end
      end
    end

    def self.inherited(child)
      child.base = self.base
      @_descendants = nil
    end

    def delete_attributes(atts)
      db.del(*atts.map { |att| key[att] })
    end

    def create_model_membership
      clear_model_membership if _type
      self.class.all << self
      root.all << self if self.class != root
    end

    def delete_model_membership
      key.del
      self.class.all.delete(self)
      root.all.delete(self)  if self.class != root
    end

    def clear_model_membership
      root.polymorphs.each{|k| k.all.delete(self) unless _type === k }
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

    # Get the value of a specific attribute. An important fact about
    # attributes in Ohm is that they are all loaded lazily.
    #
    # @param  [Symbol] att The attribute you you want to get.
    # @return [String] The value of att.
    def read_local(att)
      @_attributes[att]
    end

    # Write the value of an attribute locally, without persisting it.
    #
    # @param  [Symbol] att The attribute you want to set.
    # @param  [#to_s]  value The value of the attribute you want to set.
    # @return [#to_s]  returns value set
    def write_local(att, value)
      changed! if read_local( att ) != _write_local(att, value)
    end

    def _write_local(att, value)
      @_attributes[att] = value
    end
    
    # Used internally be the @_attributes hash to lazily load attributes
    # when you need them. You may also use this in your code if you know what
    # you are doing.
    #
    # @param  [Symbol] att The attribute you you want to get.
    # @return [String] The value of att.
    def lazy_fetch(att)
      self.class.read_remote(key,att) unless new?
    end
    
    # Used internally to read a remote attribute and force the encoding
    #
    # @param  [Symbol] att The attribute you you want to get.
    # @return [String] The value of att.
    def self.read_remote(key,att)
      value = key.hget(att)
      value.respond_to?(:force_encoding) ?
        value.force_encoding("UTF-8") :
        value
    end

    # Read attributes en masse locally.
    def read_locals(attrs)
      attrs.map do |att|
        send(att)
      end
    end

    # Read attributes en masse remotely.
    #FIXME implement prefetch, hmget etc
    def read_remotes(attrs)
      attrs.map do |att|
        read_remote(att)
      end
    end

    # Get the index name for a specific index and value pair. The return value
    # is an instance of {Ohm::Key}, which you can readily do Redis operations
    # on.
    #
    # @example
    #
    #   class Post < Ohm::Model
    #     attribute :title
    #     index :title
    #   end
    #
    #   post = Post.create(:title => "Foo")
    #   key = Post.index_key_for(:title, "Foo")
    #   key == "Post:title:Rm9v"
    #   key.scard == 1
    #   key.smembers == [post.id]
    #   # => true
    #
    # @param [Symbol] name The name of the index.
    # @param [#to_s]  value The value for the index.
    # @return [Ohm::Key] A {Ohm::Key key} which you can treat as a string,
    #                    but also do Redis operations on.
    def self.index_key_for(name, value)
      raise IndexNotFound, name unless indices.include?(name)
      key_for(name, value, :index)
    end

    # generate a given kind of key. kind = [:index, :union, ...]
    def self.key_for(name, value, kind = :index)
#      debug { "Ohm#key_for:#{name}.#{kind} #{value}"}
      root.key[name][encode(value)]
    end

    # Thin wrapper around {Ohm::Model.index_key_for}.
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

    def lock_expired?(timestamp)
      timestamp.to_f < Time.now.to_f
    end
  end
end