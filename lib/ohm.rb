require "rubygems"
require "redis"

module Ohm
  module Validations
    def valid?
      errors.clear
      validate
      errors.empty?
    end

  private

    def validate
    end

    def assert_format(att, format)
      if assert_present(att)
        assert attribute_value(att).match(format), [att, :format]
      end
    end

    def assert_present(att)
      if assert_not_nil(att)
        assert attribute_value(att).any?, [att, :empty]
      end
    end

    def assert_not_nil(att)
      assert attribute_value(att), [att, :nil]
    end

    def assert(value, error)
      value or errors.push(error) && false
    end

    def errors
      @errors ||= []
    end

    def attribute_value(att)
      instance_variable_get("@#{att}")
    end
  end

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
        db.push_tail(key, value)
      end
    end

    class Set < Collection
      def retrieve
        db.set_members(key).sort
      end

      def << value
        db.set_add(key, value)
      end

      def delete(value)
        db.set_delete(key, value)
      end
    end
  end

  class Model
    include Validations

    ModelIsNew = Class.new(StandardError)

    @@attributes = Hash.new { |hash, key| hash[key] = [] }
    @@collections = Hash.new { |hash, key| hash[key] = [] }

    attr_accessor :id

    def self.attribute(name)
      attr_writer(name)
      attr_value_reader(name)
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

    def self.attr_value_reader(name)
      class_eval <<-EOS
        def #{name}
          @#{name} ||= db[key("#{name}")]
        end
      EOS
    end

    def self.attr_list_reader(name)
      class_eval <<-EOS
        def #{name}
          Attributes::List.new(db, key("#{name}"))
        end
      EOS
    end

    def self.attr_set_reader(name)
      class_eval <<-EOS
        def #{name}
          Attributes::Set.new(db, key("#{name}"))
        end
      EOS
    end

    def self.exists?(id)
      db.set_member?(key, id)
    end

    def self.[](id)
      new(:id => id) if exists?(id)
    end

    def self.all
      db.set_members(key).map do |id|
        new(:id => id)
      end
    end

    def self.attributes
      @@attributes[self]
    end

    def self.collections
      @@collections[self]
    end

    def self.create(*args)
      new(*args).create
    end

    def initialize(attrs = {})
      attrs.each do |key, value|
        send(:"#{key}=", value)
      end
    end

    def create
      return unless valid?
      self.id = self.class.next_id
      db.set_add(self.class.key, self.id)
      save!
    end

    def save
      return unless valid?
      save!
    end

    def delete
      collections.each do |collection|
        db.delete(key(collection))
      end

      attributes.each do |attribute|
        db.delete(key(attribute))
      end

      db.set_delete(self.class.key, id)
      db.delete(key)

      self
    end

    def attributes
      self.class.attributes
    end

    def collections
      self.class.collections
    end

  private

    def self.db
      $redis
    end

    def self.key(*args)
      args.unshift(self).join(":")
    end

    def self.next_id
      db.incr(key("id"))
    end

    def db
      self.class.db
    end

    def key(*args)
      raise ModelIsNew unless id
      self.class.key(id, *args)
    end

    def save!
      attributes.each { |att| db[key(att)] = send(att) }
      self
    end
  end
end
