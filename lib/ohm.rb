require "rubygems"
require File.join(File.dirname(__FILE__), "ohm", "redis")
require File.join(File.dirname(__FILE__), "ohm", "validations")

module Ohm
  def key(*args)
    args.join(":")
  end

  module_function :key

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
        db.list_range(key, 0, -1)
      end

      def << value
        super(value) if db.push_tail(key, value)
      end
    end

    class Set < Collection
      def retrieve
        db.set_members(key).sort
      end

      def << value
        super(value) if db.set_add(key, value)
      end

      def delete(value)
        super(value) if db.set_delete(key, value)
      end

      def include?(value)
        db.set_member?(key, value)
      end
    end
  end

  class Model
    module Validations
      include Ohm::Validations

      def assert_unique(attrs)
        index_key = index_key_for(attrs, read_locals(attrs))
        assert(db.set_count(index_key).zero? || db.set_member?(index_key, id), [attrs, :not_unique])
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

    # TODO Add a method that receives several arguments and returns a
    # string with the values separated by colons.
    def self.find(attribute, value)
      # filter("#{attribute}:#{value}")
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
      $redis
    end

    def self.key(*args)
      Ohm.key(*args.unshift(self))
    end

    def self.filter(name)
      db.set_members(key(name)).map do |id|
        new(:id => id)
      end
    end

    def self.exists?(id)
      db.set_member?(key(:all), id)
    end

    def initialize_id
      self.id = db.incr(self.class.key("id"))
    end

    def db
      self.class.db
    end

    def delete_attributes(atts)
      atts.each do |att|
        db.delete(key(att))
      end
    end

    def create_model_membership
      db.set_add(self.class.key(:all), id)
    end

    def delete_model_membership
      db.set_delete(self.class.key(:all), id)
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
        db.set_add(index_key_for(attrs, read_locals(attrs)), id)
      end
    end

    def delete_from_indices
      indices.each do |attrs|
        db.set_delete(index_key_for(attrs, read_remotes(attrs)), id)
      end
    end

    def read_local(att)
      @_attributes[att]
    end

    def write_local(att, value)
      @_attributes[att] = value
    end

    def read_remote(att)
      id && db[key(att)]
    end

    def write_remote(att, value)
      db[key(att)] = value
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
