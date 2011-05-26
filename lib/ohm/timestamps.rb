require 'ohm/typecast'
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
    Timestamp = Ohm::Types::Timestamp
    
    def self.included(base)
      base.send(:include, Ohm::Typecast)
      base.attribute :created_at, Timestamp
      base.attribute :updated_at, Timestamp
    end

  protected
    def write
      ts = Timestamp.now.to_s
      self.updated_at = ts
      # set created_at here too so it is the same as the first updated_at
      self.created_at ||= ts
      super
    end
  end
end
  
