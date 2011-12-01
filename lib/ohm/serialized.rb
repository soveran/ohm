require 'bigdecimal'
require 'time'
require 'date'
require 'yajl/json_gem'  unless defined? JSON

module Ohm

  # Serializers should be symmetric, i.e.  to_str(to_val( s )) == s and to_val(to_str( v )) == v
  class Serializer
    attr :type
    attr_accessor :options
    
    def initialize(type, options={})
      @type = type
      @options = options
    end

    def to_val( str )
      @type.respond_to?(:to_val) ? @type.to_val( str ) : @type.new(str)  unless str.nil?
    end
    
    def to_str( val )
      val.respond_to?(:to_str) ? val.to_str : val.to_s  unless val.nil?
    end
    
    def key_for( val )
      to_str( @type === val ? val : to_val( str ) )
    end
    
    def self.default(type, options={})
      # try to find a serializer for the type in the type, in the current scope, or in Ohm::Serializers
      # or just return a generic serializer if not found
      klass = ( find_class("#{type}::Serializer") || 
                find_class("#{type}Serializer") ||
                find_class("Ohm::Serializers::#{type}Serializer") )
#      puts "Serializer.default: #{type}: #{klass.inspect}"
      (klass || self).new(type, options)
    end

    def inspect
      "<#{self.class.name}:#{type} options=#{options}>"
    end

   protected
    def self.find_class( name )
      klass = constantize( name ) rescue nil
      klass unless Ohm::Model::Wrapper === klass
    end
  end

  module Serializers
    Serializer = Ohm::Serializer
    
    class SymbolSerializer < Serializer
      def initialize(*args); super( Symbol, args.extract_options! ); end
      def to_val( str )
        str.to_sym if str
      end
    end

    class IntegerSerializer < Serializer
      def initialize(*args); super( Fixnum, args.extract_options! ); end
      def to_val( str )
        Integer(str) if str
      end
    end

    class FloatSerializer < Serializer
      def initialize(*args); super( Float, args.extract_options! ); end
      def to_val( str )
        Float(str) if str
      end
    end

    class DecimalSerializer < Serializer
      def initialize(*args); super( BigDecimal, args.extract_options! ); end
      def to_val( str )
        BigDecimal(str) if str
      end
    end

    class DateSerializer < Serializer
      def initialize(*args); super( Date, args.extract_options! ); end
      
      def to_str( val )
        val.iso8601 if @type === val
      end
      
      ISO8601 = /\A\d{4}-\d{2}-\d{2}\Z/
      
      def to_val( str )
        unless str.nil? || @type === str
          s = str.to_s
          @type.parse( s ) if s =~ ISO8601
        end
      end
    end

    class TimeSerializer < Serializer
      def initialize(*args); super( Time, args.extract_options! ); end
      
      ISO8601 = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.[0-9]*)?(Z|[-+]\d{2}?(:\d{2})?)\Z/
      
      def to_str( val )
        val.iso8601(options[:precision] || 0) if @type === val
      end

      def to_val( str )
        unless str.nil? || @type === str
          s = str.to_s
          @type.parse( s ) if s =~ ISO8601
        end
      end
    end
    
    class JSONSerializer < Serializer
      def initialize(type, options={})
        super( type, { symbolize_keys: true }.merge( options ) )
      end

      def to_val( str )
        JSON.parse( str, options ) if str  #TODO options.slice(:symbolize_keys)
      rescue JSON::ParserError
        nil
      end
      
      def to_str( val )
        JSON.generate( val, options ) if val
      rescue JSON::GeneratorError
        val.to_s
      end
    end
    
    class HashSerializer < JSONSerializer
      def initialize(*args)
        super( Hash, args.extract_options!)
      end
    end
    
    class ArraySerializer < JSONSerializer
      def initialize(*args)
        super( Array, args.extract_options! )
      end
    end
  end

  module Types
    
    Decimal = BigDecimal

    class Boolean
      attr_accessor :value
      def initialize(value=false)
        @value = to_val(value)
      end
      
      def to_s
        @value.to_s
      end

      def self.to_val(value)
        case value
        when 'false', false, '0', 0, 'n', 'N' then false
        when 'true',  true,  '1', 1, 'y', 'Y'  then true
        end
      end

      Serializer = Ohm::Serializer
    end
  end
  
  module Serialized
    def self.included(base)
      base.send(:include, Ohm::Types)
      base.send(:include, Ohm::Serializers)
      base.extend ClassMethods
    end

    # Parse str for attribute name with given serializer
    # Default is to call serializer.to_val
    # This gives a convenient override point for simple customizations
    def parse( name, str, serializer = _serializer(name) )
#      puts "parse: _serializer(#{name}): #{serializer.inspect}"
      serializer.to_val( str )
     rescue StandardError => e
      debug { "parse: #{name} #{str} #{serializer}: error #{e.inspect}" }
      nil
    end

    # Get and serialize the attribute value for att using the associated serializer
    # Called when writing the object's attributes to the db
    def serialize( att, val=send(att) )
      serializer = _serializer(att)
      serializer ? serializer.to_str(val) || val : super
    end

    module ClassMethods
      
      # Allow for first-class attributes without proxies
      # Values are deserialized when accessed and reserialized on write/save to db, if valid
      # Default serialization is with to_s and deserialization with new(s)
      def attribute(name, type = String, options = {})
        options = options.dup
  
        attributes(self) << name unless attributes.include?(name)
        types(root)[name] = type
        
        serializer( name, options.delete(:serializer), options )
        define_attribute( name, type, options )
      end

      # Find or declare a serializer for given attribute type by model class
      # Serializer may be set for this model subclass, our root class or globally for the base model
      # Serializer may be further overridden via the attribute serializer: option
      # All built-in serializers accept the default: val option to initialize the attribute
      #
      # @example
      #
      # class MyModel < Ohm::Model
      #   # serialize all Date attributes with MyDateSerializer, and initialize with a default value of today
      #   serializer Date, MyDateSerializer, default: Date.today
      #   attribute start_date, Date
      #
      #   # symbolize the keys of just this hash attribute
      #   attribute flags, Hash, serializer: SymbolizedKeysHashSerializer.new
      #
      #   # another way is using the built-in option of the default HashSerializer
      #   attribute flags, Hash, symbolize_keys: true, default: {}
      #
      # end
      #
      def serializer(type_or_name, *args)
        options = args.extract_options!
        serializer = args.shift
        # allow subclasses to override serializers and options by type or by name
        type = ( Class === type_or_name )? type_or_name : types[type_or_name]
        # if given a serializer instance, use it; if given a class instantiate it or the default serializer with the given options
        if serializer || !options.empty?
          serializer = serializer.new(options) if Class === serializer 
          serializer ||= Serializer.default(type, options)
          serializers(self)[type_or_name] = serializer
        else
          serializers(self).delete(type_or_name)
        end
      end

      # serialize the key value
      def key_for(name, value, kind = :index)
        #TODO serializers for indexed transient attributes?
        serializer = _serializer(name)
        if serializer
          root.key[name][encode( ( serializer.key_for(value) rescue nil ) || value )]
        else
          super
        end
      end
  
    private
      # find the serializer by attribute name or type
      def _serializer(name)
        type = types[name]
        # flatten and cache all the serializers up the tree
        @_serializers ||= all_ancestors(serializers(nil)).reverse.reduce(&:merge)
        @_serializers[name] || @_serializers[type] || ( serializers(base)[type] ||= Serializer.default(type) if type )
      end
     
      # Define the attribute accessors. override this to add option processing per type or per attribute
      # Note that call overhead for class_eval-defined methods is much lower than for define_method
      # The attribute maybe assigned a value of the declared type, or a value which can be deserialized to the declared type
      def define_attribute( name, type, options )
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            unless #{type} === ( v = read_local(:#{name}) )
              _write_local(:#{name}, v = parse( :#{name}, v ) || v ) if v
            end
            v
          end
          
          def #{name}=( v )
            write_local(:#{name}, v)
          end
        RUBY
      end
    end

    # instance methods
    
    # override to provide default value for initialization of typed attributes
    def lazy_fetch(att)
      unless ( v = super )
        v = ( s = _serializer(att) )? s.options[:default] : nil
        # if the default value is a proc, call it optionally passing the obj and att
        v = v.call(*[self,att][0...v.arity]) if Proc === v
      end
      v
    end

    # convenience method to get serializer for attribute/type
    def _serializer(name)
      self.class.send(:_serializer, name)
    end    

  end
end
