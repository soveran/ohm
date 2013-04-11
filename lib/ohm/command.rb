module Ohm
  class Command
    def self.[](operation, head, *tail)
      return head if tail.empty?

      new(operation, head, *tail)
    end

    attr :operation
    attr :args
    attr :keys

    def initialize(operation, *args)
      @operation = operation
      @args = args
      @keys = []
    end

    def call(nido, redis)
      newkey(nido, redis) do |key|
        redis.call(@operation, key, *params(nido, redis))
      end
    end

    def clean
      keys.each do |key, redis|
        redis.call("DEL", key)
      end

      subcommands.each { |cmd| cmd.clean }
    end

  private
    def subcommands
      args.select { |arg| arg.respond_to?(:call) }
    end

    def params(nido, redis)
      args.map { |arg| arg.respond_to?(:call) ? arg.call(nido, redis) : arg }
    end

    def newkey(nido, redis)
      key = nido[SecureRandom.hex(32)]
      keys << [key, redis]

      yield key

      return key
    end
  end
end
