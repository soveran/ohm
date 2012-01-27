require "set"

module Ohm
  class Transaction
    attr :phase

    def self.define(&block)
      new.tap(&block)
    end

    def initialize(*transactions)
      @phase = Hash.new { |h, k| h[k] = ::Set.new }

      transactions.each do |t|
        append(t)
      end
    end

    def append(t)
      t.phase.each do |key, values|
        phase[key].merge(values)
      end
    end

    def watch(*keys)
      phase[:watch] += keys
    end

    def read(&block)
      phase[:read] << block
    end

    def write(&block)
      phase[:write] << block
    end

    def before(&block)
      phase[:before] << block
    end

    def after(&block)
      phase[:after] << block
    end

    def commit(db)
      run(phase[:before])

      loop do
        if phase[:watch].any?
          db.watch(*phase[:watch])
        end

        run(phase[:read])

        break if db.multi do
          run(phase[:write])
        end
      end

      run(phase[:after])
    end

    def run(procs)
      procs.each { |p| p.call }
    end
  end
end
