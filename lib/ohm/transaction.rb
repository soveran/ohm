require "set"

module Ohm
  class Transaction
    attr_accessor :blocks

    def self.define(&block)
      new.tap(&block)
    end

    def initialize(*transactions)
      @blocks = Hash.new { |h, k| h[k] = ::Set.new }

      transactions.each do |t|
        append(t)
      end
    end

    def append(t)
      t.blocks.each do |key, values|
        blocks[key].merge(values)
      end
    end

    def watch(*keys)
      @blocks[:watch] += keys
    end

    def read(&block)
      @blocks[:read] << block
    end

    def write(&block)
      @blocks[:write] << block
    end

    def before(&block)
      @blocks[:before] << block
    end

    def after(&block)
      @blocks[:after] << block
    end

    def commit(db)
      run(blocks[:before])

      loop do
        if blocks[:watch].any?
          db.watch(*blocks[:watch])
        end

        run(blocks[:read])

        break if db.multi do
          run(blocks[:write])
        end
      end

      run(blocks[:after])
    end

    def run(procs)
      procs.each { |p| p.call }
    end
  end
end
