unless nil.respond_to?(:empty?)
  class NilClass
    def empty?; true; end
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
      constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
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

