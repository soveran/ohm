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

unless Object.new.respond_to?(:tap)
  class Object
    def tap
      yield(self)
      self
    end
  end
end
