#
#
# Rails Candy
#
# On application.rb
#
#    require "action_controller/railtie"
#    require "active_resource/railtie"
#    require "active_support/railtie"
#    require "action_view/railtie"
#
require "singleton"
require "ohm"
#require "ohm/config"
require "ohm/railties/model"
require "rails/ohm"

module Rails #:nodoc:
  module Ohm #:nodoc:
    class Railtie < Rails::Railtie #:nodoc:

      config.generators.orm :ohm, :migration => false

      rake_tasks do
        load "ohm/railties/database.rake"
      end

      # Exposes Ohm's configuration to the Rails application configuration.
      #
      # Example:
      #
      #   module MyApplication
      #     class Application < Rails::Application
      #       config.ohm.logger = Logger.new($stdout, :warn)
      #       config.ohm.reconnect_time = 10
      #     end
      #   end
     # config.ohm = ::Ohm::Config.instance

      # Initialize Ohm. This will look for a ohm.yml in the config
      # directory and configure ohm appropriately.
      #
      # Example ohm.yml:
      #
      #   defaults: &defaults
      #     host: localhost
      #     slaves:
      #       # - host: localhost
      #         # port: 6380
      #       # - host: localhost
      #         # port: 6381
      #     allow_dynamic_fields: false
      #     parameterize_keys: false
      #     persist_in_safe_mode: false
      #
      #   development:
      #     <<: *defaults
      #     database: ohm
      initializer "setup database" do
        config_file = Rails.root.join("config", "ohm.yml")
        if config_file.file?
          settings = YAML.load(ERB.new(config_file.read).result)[Rails.env]
          if settings.present?
            puts "[Ohm] Connecting to #{Rails.env} env, DB ##{settings['db']}."
            ::Ohm.connect(settings)
          end
        end
      end

      # # After initialization we will attempt to connect to the database, if
      # # we get an exception and can't find a ohm.yml we will alert the user
      # # to generate one.
      # initializer "verify that ohm is configured" do
      #   config.after_initialize do
      #     begin
      #       ::Ohm.master
      #     rescue ::Ohm::Errors::InvalidDatabase => e
      #       unless Rails.root.join("config", "ohm.yml").file?
      #         puts "\nOhm config not found. Create a config file at: config/ohm.yml"
      #         puts "to generate one run: rails generate ohm:config\n\n"
      #       end
      #     end
      #   end
      # end

      # Due to all models not getting loaded and messing up inheritance queries
      # and indexing, we need to preload the models in order to address this.
      #
      # This will happen every request in development, once in ther other
      # environments.
      # initializer "preload all application models" do |app|
      #   config.to_prepare do
      #     ::Rails::Ohm.load_models(app)
      #   end
      # end

      # initializer "reconnect to master if application is preloaded" do
      #   config.after_initialize do

      #     # Unicorn clears the START_CTX when a worker is forked, so if we have
      #     # data in START_CTX then we know we're being preloaded. Unicorn does
      #     # not provide application-level hooks for executing code after the
      #     # process has forked, so we reconnect lazily.
      #     if defined?(Unicorn) && !Unicorn::HttpServer::START_CTX.empty?
      #       ::Ohm.reconnect!(false)
      #     end

      #     # Passenger provides the :starting_worker_process event for executing
      #     # code after it has forked, so we use that and reconnect immediately.
      #     if defined?(PhusionPassenger)
      #       PhusionPassenger.on_event(:starting_worker_process) do |forked|
      #         if forked
      #           ::Ohm.reconnect!
      #         end
      #       end
      #     end
      #   end
     # end
    end
  end
end
