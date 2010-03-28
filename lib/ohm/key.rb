module Ohm

  # Represents a key in Redis.
  class Key
    attr :parts
    attr :glue
    attr :namespace

    def self.[](*parts)
      Key.new(parts)
    end

    def initialize(parts, glue = ":", namespace = [])
      @parts = parts
      @glue = glue
      @namespace = namespace
    end

    def sub_keys
      parts.map {|k| k.glue == ":" ? k : k.volatile }
    end

    def append(*parts)
      @parts += parts
      self
    end

    def eql?(other)
      to_s == other.to_s
    end

    alias == eql?

    def to_s
      (namespace + [@parts.join(glue)]).join(":")
    end

    alias inspect to_s
    alias to_str to_s

    def volatile
      @namespace = [:~]
      self
    end

    def group(glue = self.glue)
      Key.new([self], glue, namespace.slice!(0, namespace.size))
    end
  end
end
