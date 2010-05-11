begin
  require "batch"
rescue LoadError => e
  e.message << "\nTry `gem install batch`."
end

module Ohm
  module Utils
    class Upgrade
      def redis
        Ohm.redis
      end

      attr :models
      attr :types

      def initialize(models)
        @models = models
        @types = Hash.new { |hash, model| hash[model] = {} }
      end

      def run
        models.each do |model|
          ns = Ohm::Key[model]

          puts "Upgrading #{model}..."

          Batch.each(redis.smembers(ns[:all])) do |id|
            instance = ns[id]

            attrs = []
            deletes = []

            redis.keys(instance["*"]).each do |key|
              field = key[instance.size.succ..-1]

              type = (types[model][field] ||= redis.type(key).to_sym)

              if type == :string
                attrs << field
                attrs << redis.get(key)
                deletes << key
              end
            end

            redis.hmset(instance, *attrs)
            redis.del(*deletes)
          end
        end
      end
    end
  end
end
