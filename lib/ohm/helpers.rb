# some core_ext methods poached  from active_support
unless nil.respond_to?(:empty?)
  class NilClass
    def empty?; true; end
  end
end

unless Array.respond_to?(:wrap)
  class Array
  # File activesupport/lib/active_support/core_ext/array/wrap.rb, line 39
    def self.wrap(object)
      if object.nil?
        []
      elsif object.respond_to?(:to_ary)
        object.to_ary
      else
        [object]
      end
    end
  end
end

unless Array.respond_to?(:extract_options!)
  class Array
    def extract_options!(*options)
      ( options.pop if Hash === options.last ) || {}
    end
  end
end

unless defined?(silence_warnings)
  def silence_warnings; yield; end
end

unless defined?(constantize)
  # File activesupport/lib/active_support/inflector/methods.rb, line 107
  
  def constantize(camel_cased_word)
    names = camel_cased_word.split('::')
    names.shift if names.empty? || names.first.empty?
  
    constant = Object
    names.each do |name|
      constant = constant.const_defined?(name,false) ? constant.const_get(name) : constant.const_missing(name)
    end
    constant
  end
end

unless defined?(Class.descendants)
  class Class
  # File activesupport/lib/active_support/core_ext/class/subclasses.rb, line 29
    def descendants
      descendants = []
      ObjectSpace.each_object(Class) do |k|
        descendants.unshift k if k < self
      end
      descendants.uniq!
      descendants
    end
  end
end

