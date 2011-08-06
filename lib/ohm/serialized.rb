require 'bigdecimal'
require 'time'
require 'date'
require 'yajl/json_gem' unless defined? JSON

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
      !str.nil? && ( @type.respond_to?(:to_val) ? @type.to_val( str ) : @type.new(str) )
    end
    
    def to_str( val )
      !val.nil? && ( val.respond_to?(:to_str) ? val.to_str : val.to_s )
    end
    
    def extract_options!(*options)
      ( options.pop if Hash === options.last ) || {}
    end
    
    def self.default(type)
      # try to find a serializer for the type in the type, in the current scope, or in Ohm::Serializers
      # or just return a generic serializer if not found
      klass = ( constantize("#{type}::Serializer") rescue nil || 
                constantize("#{type}Serializer") rescue nil ||
                constantize("Ohm::Serializers::#{type}Serializer") rescue nil )
      (klass || self).new(type)
    end
  end

  module Serializers
    Serializer = Ohm::Serializer
    
    class IntegerSerializer < Serializer
      def initialize(type=nil); super( Fixnum ); end
      def to_val( str )
        str.to_i if str
      end
    end

    class FloatSerializer < Serializer
      def initialize(type=nil); super( Float ); end
      def to_val( str )
        str.to_f if str
      end
    end

    class DecimalSerializer < Serializer
      def initialize(type=nil); super( BigDecimal ); end
      def to_val( str )
        BigDecimal( str ) if str
      end
    end
    
    class DateTimeSerializer < Serializer
      def to_val( str )
        @type.parse( str ) if String === str
      end
    end
    
    class DateSerializer < DateTimeSerializer
      def initialize(*args)
        super(Date, extract_options!(*args))
      end
      
      def to_str( val )
        val.iso8601 if val
      end
    end
    
    class TimeSerializer < DateTimeSerializer
      def initialize(*args)
        super(Time, extract_options!(*args))
      end
      
      def to_str( val )
        val.iso8601(options[:precision] || 0) if val
      end
    end
    
    class JSONSerializer < Serializer
      def initialize(type=nil, options={ symbolize_keys:true })
        super
      end

      def to_val( str )
        JSON.parse( str, options ) if str
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
        super( Hash, { symbolize_keys: true }.merge( extract_options!(*args) ) )
      end
    end
    
    class ArraySerializer < JSONSerializer
      def initialize(*args)
        super( Array, { symbolize_keys: true }.merge( extract_options!(*args) ) )
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
    def parse( name, str, serializer )
      d = serializer.to_val( str )
    rescue StandardError => e
      puts  "parse: #{name} #{str} #{serializer}: error #{e.inspect}"
      nil
    end

    module ClassMethods
      # Allow for first-class attributes without proxies
      # Values are deserialized when accessed and reserialized on validation, if valid
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
      #
      # @example
      #
      # class MyModel < Ohm::Model
      #   # serialize all Date attributes with MyDateSerializer instead of the default
      #   serializer Date, MyDateSerializer
      #   attribute start_date, Date
      #
      #   # symbolize the keys of just this hash attribute
      #   attribute flags, Hash, serializer: SymbolizedKeysHashSerializer.new
      #
      #   # another way is using the built-in option of the default HashSerializer
      #   attribute flags, Hash, symbolize_keys: true
      #
      # end
      #
      def serializer(type_or_name, serializer, options={})
        # allow subclasses to override serializers by type, but define per-attribute serializers on the root
        if serializer
          puts "serializer: #{type_or_name} #{serializer.inspect} #{options}"
          serializer = serializer.new(options) if Class === serializer
          serializers(self)[type_or_name] = serializer
        else
          serializers(self).delete(type_or_name)
        end
      end
  
    protected
      # find the serializer by attribute name or type
      def _serializer(name, type, klass=self)
        serializers(klass)[name] || serializers(klass)[type] || serializers(root)[type] || ( serializers(base)[type] ||= Serializer.default(type) )
      end
     
      # Define the attribute accessors. override this to add option processing per type or per attribute
      # Note that call overhead for class_eval-defined methods is much lower than for define_method
      # The attribute maybe assigned a value of the declared type, or a value which can be deserialized to the declared type
      def define_attribute( name, type, options )
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            unless #{type} === ( v = read_local(:#{name}) )
              puts "#{name} accessor: #{type}: \#{v} \#{v.class}"
              _write_local(:#{name}, v = parse( :#{name}, v, self.class.send(:_serializer, :#{name}, #{type}) ) || v ) if v
            end
            v
          end
          
          def #{name}=( v )
            unless String === v
              v = self.class.send(:_serializer, :#{name}, #{type}).to_str(v) if v
            end
            write_local(:#{name}, v)
          end
        RUBY
      end
    end
    
  end
end
