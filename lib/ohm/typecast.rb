require 'bigdecimal'
require 'time'
require 'date'
require 'json'
require 'forwardable'

module Ohm
  # Provides all the primitive types. The following are included:
  #
  # * String
  # * Decimal
  # * Integer
  # * Float
  # * Date
  # * Time
  # * Hash
  # * Array
  # * Boolean
  module Types
    def self.defined?(type)
      @constants ||= constants.map(&:to_s)
      @constants.include?(type.to_s)
    end

    def self.[](type)
      const_get(type.to_s.split('::').last)
    end

    class Base < BasicObject
      class Exception < ::Exception; end

      extend ::Forwardable

      @@delegation_blacklist = [
        :==, :to_s, :initialize, :inspect, :object_id, :__send__, :__id__,
        :respond_to?
      ]

      def self.[](value)
        return empty  if value.to_s.empty?

        new(value)
      end

      def self.empty
        defined?(self::RAW) ? self::RAW.new : nil
      end

      def self.delegate_to(klass, except = @@delegation_blacklist)
        methods = klass.public_instance_methods.map(&:to_sym) - except
        def_delegators :object, *methods
      end

      def inspect
        @raw.inspect
      end
    end

    class Primitive < Base
      def initialize(value)
        @raw = value
      end

      def to_s
        @raw.to_s
      end

      def ==(other)
        to_s == other.to_s
      end

      def respond_to?(method)
        object.respond_to?(method)
      rescue ::ArgumentError
        @raw.respond_to?(method)
      end

      def object
        @raw
      end
    end

    class String < Primitive
      delegate_to ::String
    end

    class Decimal < Primitive
      delegate_to ::BigDecimal

      def object
        ::Kernel::BigDecimal(@raw)
      end
    end

    class Integer < Primitive
      delegate_to ::Fixnum

      def object
        ::Kernel::Integer(@raw)
      end
    end
    Number = Integer

    class Float < Primitive
      delegate_to ::Float

      def object
        ::Kernel::Float(@raw)
      end
    end

    # Time#at is way faster than #parse
    class Time < Primitive
      delegate_to ::Time

      def object
        ::Time.at(@raw).utc
      end
    end

    class Date < Primitive
      delegate_to ::Date

      def object
        ::Date.parse(@raw)
      end
    end

    class Boolean
      def self.[](value)
        case value
        when 'false', false, '0', 0 then false
        when 'true',  true,  '1', 1  then true
        end
      end
    end

    class Serialized < Base
      attr :object

      def initialize(raw)
        @object = case raw
        when self.class::RAW
          raw
        when ::String
          begin
            ::JSON.parse(raw)
          rescue ::JSON::ParserError
            raw
          end
        when self.class
          raw.object
        else
          ::Kernel.raise ::TypeError,
            "%s does not accept %s" % [self.class, raw.inspect]
        end
      end

      def ==(other)
        object == other
      end

      def to_s
        object.to_json
      end
      alias :inspect :to_s

      def respond_to?(method)
        object.respond_to?(method)
      end
    end

    class Hash < Serialized
      RAW = ::Hash

      delegate_to ::Hash

      # @private since basic object doesn't include a #class we need
      # to define this manually
      def class
        ::Ohm::Types::Hash
      end
    end

    class Array < Serialized
      RAW = ::Array

      delegate_to ::Array

      # @private since basic object doesn't include a #class we need
      # to define this manually
      def class
        ::Ohm::Types::Array
      end
    end
  end

  # Provides unobtrusive, non-explosive typecasting.Instead of exploding on set
  # of an invalid value, this module takes the approach of just taking in
  # parameters and letting you do validation yourself. The only thing this
  # module does for you is the boilerplate casting you might need to do.
  #
  # @example
  #
  #   # without typecasting
  #   class Item < Ohm::Model
  #     attribute :price
  #     attribute :posted
  #   end
  #
  #   item = Item.create(:price => 299, :posted => Time.now.utc)
  #   item = Item[item.id]
  #
  #   # now when you try and grab `item.price`, its a string.
  #   "299" == item.price
  #   # => true
  #
  #   # you can opt to manually cast everytime, or do it in the model, i.e.
  #
  #   class Item
  #     def price
  #       BigDecimal(read_local(:price))
  #     end
  #   end
  #
  # The Typecasted way
  # ------------------
  #
  #   class Item < Ohm::Model
  #     include Ohm::Typecast
  #
  #     attribute :price, Decimal
  #     attribute :posted, Time
  #   end
  #
  #   item = Item.create(:price => "299", :posted => Time.now.utc)
  #   item = Item[item.id]
  #   item.price.class == Ohm::Types::Decimal
  #   # => true
  #
  #   item.price.to_s == "299"
  #   # => true
  #
  #   item.price * 2 == 598
  #   # => true
  #
  #   item.posted.strftime('%m/%d/%Y')
  #   # => works!!!
  module Typecast
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      # Defines a typecasted attribute.
      #
      # @example
      #
      #   class User < Ohm::Model
      #     include Ohm::Typecast
      #
      #     attribute :birthday, Date
      #     attribute :last_login, Time
      #     attribute :age, Integer
      #     attribute :spending, Decimal
      #     attribute :score, Float
      #   end
      #
      #   user = User.new(:birthday => "2000-01-01")
      #   user.birthday.month == 1
      #   # => true
      #
      #   user.birthday.year == 2000
      #   # => true
      #
      #   user.birthday.day == 1
      #   # => true
      #
      #   user = User.new(:age => 20)
      #   user.age - 1 == 19
      #   => true
      #
      # @param [Symbol] name the name of the attribute to define.
      # @param [Class] type (defaults to Ohm::Types::String) a class defined in
      #                Ohm::Types. You may define custom types in Ohm::Types if
      #                you need to.
      # @return [Array] the array of attributes already defined.
      # @return [nil] if the attribute is already defined.
      def attribute(name, type = Ohm::Types::String, klass = Ohm::Types[type])
        define_method(name) do
          # Primitive types maintain a reference to the original object
          # stored in @_attributes[att]. Hence mutation works for the
          # Primitive case. For cases like Hash, Array where the value
          # is `JSON.parse`d, we need to set the actual Ohm::Types::Hash
          # (or similar) to @_attributes[att] for mutation to work.
          if klass.superclass == Ohm::Types::Primitive
            klass[read_local(name)]
          else
            write_local(name, klass[read_local(name)])
          end
        end

        define_method(:"#{name}=") do |value|
          write_local(name, klass[value].to_s)
        end

        attributes << name unless attributes.include?(name)
      end
      alias :attr :attribute

    private
      def const_missing(name)
        if Ohm::Types.defined?(name)
          Ohm::Types[name]
        else
          super
        end
      end

      def method_missing(m, *args)
        if Ohm::Types.constants.include? m.capitalize
          attr(args[0], m.capitalize)
        else
          raise NoMethodError.new("undefined method '#{m}' for #{inspect}:#{self.class}")
        end
      end

    end
  end
end
