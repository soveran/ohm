require File.join(File.dirname(__FILE__), "serialized")
module Ohm
  # Provides typecast created_at / updated_at timestamps that preserve microseconds.
  #
  # @example
  #
  #   class Post < Ohm::Model
  #     include Ohm::Timestamping
  #   end
  #
  #   post = Post.create
  #   post.created_at.to_s == Time.now.utc.to_s
  #   # => true
  #
  #   post = Post[post.id]
  #   post.save
  #   post.updated_at.to_s == Time.now.utc.to_s
  #   # => true

  module Timestamps
    # Time including microseconds
    class Timestamp < Time
      def to_str
        utc.iso8601(6)
      end
      alias_method :inspect, :to_str
      alias_method :to_s, :to_str
      
      def self.to_val( str )
        parse(str).utc
      end
      
      Serializer = Ohm::Serializer
    end
    
    def self.included(base)
      base.send(:include, Ohm::Serialized)
      base.attribute :created_at, Timestamp
      base.attribute :updated_at, Timestamp
    end

  protected
    def _create
      self.updated_at = self.created_at = Timestamp.now.to_s
      super
    end
    
    def _save
      self.updated_at = Timestamp.now.to_s
      super
    end
  end
end
  
