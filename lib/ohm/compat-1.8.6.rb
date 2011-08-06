unless "".respond_to?(:lines)
  class String

    # This version of String#lines is almost fully compatible with that
    # of Ruby 1.9. If a zero-length record separator is supplied in Ruby
    # 1.9, the string is split into paragraphs delimited by multiple
    # successive newlines. This replacement ignores that feature in
    # favor of code simplicity.
    def lines(separator = $/)
      result = split(separator).map { |part| "#{part}#{separator}" }
      result.each { |r| yield r } if block_given?
      result
    end
  end
end

unless respond_to?(:tap)
  class Object
    def tap
      yield(self)
      self
    end
  end
end

module Ohm
  if defined?(BasicObject)
    BasicObject = ::BasicObject
  elsif defined?(BlankSlate)
    BasicObject = ::BlankSlate
  else

    # If neither BasicObject (Ruby 1.9) nor BlankSlate (typically provided by Builder)
    # are present, define our simple implementation inside the Ohm module.
    class BasicObject
      instance_methods.each { |meth| undef_method(meth) unless meth =~ /\A(__|instance_eval)/ }
    end
  end

unless defined?(constantize)
  if ::RUBY_VERSION =~ /1.8/
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
end

end
