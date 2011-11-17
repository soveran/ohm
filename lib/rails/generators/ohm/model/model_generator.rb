# encoding: utf-8
require "rails/generators/ohm_generator"

module Ohm #:nodoc:
  module Generators #:nodoc:
    class ModelGenerator < Base #:nodoc:

      desc "Creates an Ohm model"
      argument :attributes, :type => :array, :default => [], :banner => "field:type field:type"

      check_class_collision

      class_option :timestamps, :type => :boolean
      # class_option :parent,     :type => :string, :desc => "The parent class for the generated model"

      def create_model_file
        template "model.rb", File.join("app/models", class_path, "#{file_name}.rb")
      end

      hook_for :test_framework
    end
  end
end
