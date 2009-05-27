require "rubygems"
require "redis"
require File.join(File.dirname(__FILE__), "ohm", "validations")

module Ohm
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

      def assert_unique(att)
        key = self.class.key(:name, name)
        assert(db.set_count(key).zero? || db.set_member?(key, id), [att, :not_unique])
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
        @_attributes[name]
      end

      define_method(:"#{name}=") do |value|
        @_attributes[name] = value
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

    def self.index(attribute)
      indices << attribute
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
      filter("#{attribute}:#{value}")
    end

    def initialize(attrs = {})
      @_attributes = Hash.new {|hash,key| hash[key] = read_attribute(key) }

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
      args.unshift(self).join(":")
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
      attributes.each { |att| db[key(att)] = send(att) }
      self
    end

    def update_indices
      delete_from_indices
      add_to_indices
    end

    def add_to_indices
      indices.each do |index|
        db.set_add(self.class.key(index, send(index)), id)
      end
    end

    def delete_from_indices
      indices.each do |index|
        db.set_delete(self.class.key(index, read_attribute(index)), id)
      end
    end

    def read_attribute(name)
      id && db[key(name)]
    end
  end
end
