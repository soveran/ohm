# encoding: utf-8
require "rails/generators/named_base"
require "rails/generators/active_model"

module Ohm #:nodoc:
  module Generators #:nodoc:
    class Base < ::Rails::Generators::NamedBase #:nodoc:

      def self.source_root
        @_ohm_source_root ||=
        File.expand_path("../#{base_name}/#{generator_name}/templates", __FILE__)
      end
    end

    class ActiveModel < ::Rails::Generators::ActiveModel #:nodoc:
      def self.all(klass)
        "#{klass}.all"
      end

      def self.find(klass, params=nil)
        "#{klass}.find(#{params})"
      end

      def self.build(klass, params=nil)
        if params
          "#{klass}.new(#{params})"
        else
          "#{klass}.new"
        end
      end

      def save
        "#{name}.save"
      end

      def update_attributes(params=nil)
        "#{name}.update_attributes(#{params})"
      end

      def errors
        "#{name}.errors"
      end

      def destroy
        "#{name}.destroy"
      end
    end
  end
end

module Rails
  module Generators
    class GeneratedAttribute #:nodoc:
      def type_class
        return "Time" if type.to_s == "datetime"
        return "String" if type.to_s == "text"
        return type.to_s.camelcase
      end
    end
  end
end
