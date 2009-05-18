require "rubygems"
require "redis"

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
    end
  end

  class Model
    ModelIsNew = Class.new(StandardError)

    @@attributes = Hash.new { |hash, key| hash[key] = [] }

    attr_accessor :id

    def self.attribute(name)
      attr_writer(name)
      attr_value_reader(name)
      attributes << name
    end

    def self.list(name)
      attr_list_reader(name)
    end

    def self.set(name)
      attr_set_reader(name)
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

    def self.create(*args)
      new(*args).create
    end

    def initialize(attrs = {})
      attrs.each do |key, value|
        send(:"#{key}=", value)
      end
    end

    def create
      self.id = self.class.next_id
      db.set_add(self.class.key, self.id)
      db[key] = true
      save
    end

    def save
      self.class.attributes.each do |name|
        db[key(name)] = send(name)
      end

      self
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
  end
end
