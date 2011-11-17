# encoding: utf-8
require 'rails/generators/ohm_generator'

module Ohm
  module Generators
    class ConfigGenerator < Rails::Generators::Base
      desc "Creates a Ohm configuration file at config/ohm.yml"

      argument :database_number, :type => :string, :optional => true

      def self.source_root
        @_ohm_source_root ||= File.expand_path("../templates", __FILE__)
      end

      def app_name
        Rails::Application.subclasses.first.parent.to_s.underscore
      end

      def create_config_file
        template 'ohm.yml', File.join('config', "ohm.yml")
      end

    end
  end
end
