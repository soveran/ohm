require "rubygems"
require "redis"

module Ohm
  class Model
    ModelIsNew = Class.new(StandardError)

    @@attributes = Hash.new { |h,k| h[k] = [] }

    attr_accessor :id

    def self.attribute(name)
      attr_writer(name)
      attr_lazy_reader(name)
      attributes << name
    end

    def self.attr_lazy_reader(name)
      class_eval <<-EOS
        def #{name}
          @#{name} ||= db[key(#{name.inspect})]
        end
      EOS
    end

    def self.[](id)
      if db[key(self, id)]
        model = new
        model.id = id
        model
      end
    end

    def self.all
      db.set_members(key(self)).map do |id|
        self[id]
      end
    end

    def self.attributes
      @@attributes[self]
    end

    def self.next_id
      db.incr(key(self, "id"))
    end

    def new?
      ! self.id
    end

    def create
      self.id = self.class.next_id
      db.set_add(self.class.key(self.class), self.id)
      db[key] = true
      save
    end

    def save
      ensure_model_exists

      self.class.attributes.each do |att|
        db[key(att)] = send(att)
      end

      self
    end

  private

    def ensure_model_exists
      raise ModelIsNew if new?
    end

    def key(*args)
      self.class.key([self.class, id] + args)
    end

    def self.key(*args)
      args.join(":")
    end

    def db
      self.class.db
    end

    def self.db
      $redis
    end
  end
end
