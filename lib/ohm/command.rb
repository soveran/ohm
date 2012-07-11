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

    def call(nest, db)
      newkey(nest) do |key|
        db.send(@operation, key, *params(nest, db))
      end
    end

    def clean
      keys.each { |key| key.del }
      subcommands.each { |cmd| cmd.clean }
    end

  private
    def subcommands
      args.select { |arg| arg.respond_to?(:call) }
    end

    def params(nest, db)
      args.map { |arg| arg.respond_to?(:call) ? arg.call(nest, db) : arg }
    end

    def newkey(nest)
      key = nest[SecureRandom.hex(32)]
      keys << key

      yield  key
      return key
    end
  end
end
