require File.join(File.dirname(__FILE__), "ohm", "redis")
require File.join(File.dirname(__FILE__), "ohm", "validations")

module Ohm
  def redis
    @redis
  end

  def connect(*attrs)
    @redis = Ohm::Redis.new(*attrs)
  end

  def flush
    @redis.flushdb
  end

  def key(*args)
    args.join(":")
  end

  module_function :key, :connect, :flush, :redis

  module Attributes
    class Collection < Array
      attr_accessor :key, :db

      def initialize(db, key)
        self.db = db
        self.key = key
        super(retrieve)
      end
    end

    class List < Collection
      def retrieve
        db.list(key)
      end

      def << value
        super(value) if db.rpush(key, value)
      end
    end

    class Set < Collection
      def retrieve
        db.smembers(key).sort
      end

      def << value
        super(value) if db.sadd(key, value)
      end

      def delete(value)
        super(value) if db.srem(key, value)
      end

      def include?(value)
        db.sismember(key, value)
      end
    end
  end

  class Model
    module Validations
      include Ohm::Validations

      def assert_unique(attrs)
        index_key = index_key_for(attrs, read_locals(attrs))
        assert(db.scard(index_key).zero? || db.sismember(index_key, id), [attrs, :not_unique])
      end
    end

    include Validations

    ModelIsNew = Class.new(StandardError)

    @@attributes = Hash.new { |hash, key| hash[key] = [] }
    @@collections = Hash.new { |hash, key| hash[key] = [] }
    @@indices = Hash.new { |hash, key| hash[key] = [] }

    attr_accessor :id

    def self.attribute(name)
      define_method(name) do
        read_local(name)
      end

      define_method(:"#{name}=") do |value|
        write_local(name, value)
      end

      attributes << name
    end

    def self.list(name)
      attr_list_reader(name)
      collections << name
    end

    def self.set(name)
      attr_set_reader(name)
      collections << name
    end

    def self.index(attrs)
      indices << attrs
    end

    def self.attr_list_reader(name)
      class_eval <<-EOS
        def #{name}
          @#{name} ||= Attributes::List.new(db, key("#{name}"))
        end
      EOS
    end

    def self.attr_set_reader(name)
      class_eval <<-EOS
        def #{name}
          @#{name} ||= Attributes::Set.new(db, key("#{name}"))
        end
      EOS
    end

    def self.[](id)
      new(:id => id) if exists?(id)
    end

    def self.all
      filter(:all)
    end

    def self.attributes
      @@attributes[self]
    end

    def self.collections
      @@collections[self]
    end

    def self.indices
      @@indices[self]
    end

    def self.create(*args)
      new(*args).create
    end

    def self.find(attribute, value)
      filter(Ohm.key(attribute, value))
    end

    def initialize(attrs = {})
      @_attributes = Hash.new {|hash,key| hash[key] = read_remote(key) }

      attrs.each do |key, value|
        send(:"#{key}=", value)
      end
    end

    def create
      return unless valid?
      initialize_id
      create_model_membership
      add_to_indices
      save!
    end

    def save
      return unless valid?
      update_indices
      save!
    end

    def delete
      delete_from_indices
      delete_attributes(collections)
      delete_attributes(attributes)
      delete_model_membership
      self
    end

    def attributes
      self.class.attributes
    end

    def collections
      self.class.collections
    end

    def indices
      self.class.indices
    end

    def ==(other)
      other.key == key
    rescue ModelIsNew
      false
    end

  protected

    def key(*args)
      raise ModelIsNew unless id
      self.class.key(id, *args)
    end

  private

    def self.db
      Ohm.redis
    end

    def self.key(*args)
      Ohm.key(*args.unshift(self))
    end

    def self.filter(name)
      db.smembers(key(name)).map do |id|
        new(:id => id)
      end
    end

    def self.exists?(id)
      db.sismember(key(:all), id)
    end

    def initialize_id
      self.id = db.incr(self.class.key("id"))
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

    def save!
      attributes.each { |att| write_remote(att, send(att)) }
      self
    end

    def update_indices
      delete_from_indices
      add_to_indices
    end

    def add_to_indices
      indices.each do |attrs|
        db.sadd(index_key_for(attrs, read_locals(attrs)), id)
      end
    end

    def delete_from_indices
      indices.each do |attrs|
        db.srem(index_key_for(attrs, read_remotes(attrs)), id)
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
      db.set(key(att), value)
    end

    def read_locals(attrs)
      attrs.map do |att|
        read_local(att)
      end
    end

    def read_remotes(attrs)
      attrs.map do |att|
        read_remote(att)
      end
    end

    def index_key_for(attrs, values)
      self.class.key *(attrs + values)
    end
  end
end
