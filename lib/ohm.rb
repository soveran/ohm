require "rubygems"
require "redis"

module Ohm
  module Attributes
    class Value
      attr_accessor :name

      def initialize(ame)
        self.name = name
      end

      def read(db, key)
        db[key]
      end

      def write(db, key, value)
        db[key] = value
      end
    end

    class Set
      attr_accessor :name

      def initialize(ame)
        self.name = name
      end

      def read(db, key)
        db.set_members(key)
      end

      def write(db, key, value)
        db.set_add(key, value)
      end
    end

    class List
      attr_accessor :name

      def initialize(ame)
        self.name = name
      end

      def read(db, key)
        db.set_members(key)
      end

      def write(db, key, value)
        db.set_add(key, value)
      end
    end
  end

  class Model
    ModelIsNew = Class.new(StandardError)

    @@attributes = Hash.new { |hash, key| hash[key] = {} }

    attr_accessor :id

    def self.attribute(name)
      attr_writer(name)
      attr_lazy_reader(name)
      attributes[name] = Attributes::Value.new(name)
    end

    def self.list(name)
      attr_writer(name)
      attr_lazy_reader(name)
      attributes[name] = Attributes::List.new(name)
    end

    def self.set(name)
      attr_writer(name)
      attr_lazy_reader(name)
      attributes[name] = Attributes::Set.new(name)
    end

    def self.attr_lazy_reader(name) :comments
      class_eval <<-EOS
        def #{name}
          @#{name} ||= self.class.attributes[:#{name}].read(db, key("#{name}"))
        end
      EOS
    end

    def self.[](id)
      if db[key(id)]
        model = new
        model.id = id
        model
      end
    end

    def self.all
      db.set_members(key).map do |id|
        self[id]
      end
    end

    def self.attributes
      @@attributes[self]
    end

    def self.next_id
      db.incr(key("id"))
    end

    def new?
      ! self.id
    end

    def create
      self.id = self.class.next_id
      db.set_add(self.class.key, self.id)
      db[key] = true
      save
    end

    def save
      verify_model_exists

      self.class.attributes.each do |name, attribute|
        attribute.write(db, key(name), send(name))
        # db[key(att)] = send(att)
      end

      self
    end

  private

    def verify_model_exists
      raise ModelIsNew if new?
    end

    def key(*args)
      self.class.key(id, *args)
    end

    def self.key(*args)
      args.unshift(self).join(":")
    end

    def db
      self.class.db
    end

    def self.db
      $redis
    end
  end
end
