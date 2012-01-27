require "set"

module Ohm
  class Transaction
    attr_accessor :observed_keys
    attr_accessor :reading_procs
    attr_accessor :writing_procs
    attr_accessor :before_procs
    attr_accessor :after_procs

    def self.define(&block)
      new.tap(&block)
    end

    def initialize(*transactions)
      @observed_keys = ::Set.new
      @reading_procs = ::Set.new
      @writing_procs = ::Set.new
      @before_procs  = ::Set.new
      @after_procs   = ::Set.new

      transactions.each do |t|
        append(t)
      end
    end

    def append(t)
      @observed_keys += t.observed_keys
      @reading_procs += t.reading_procs
      @writing_procs += t.writing_procs
      @before_procs  += t.before_procs
      @after_procs   += t.after_procs
    end

    def watch(*keys)
      @observed_keys += keys
    end

    def read(&block)
      @reading_procs << block
    end

    def write(&block)
      @writing_procs << block
    end

    def before(&block)
      @before_procs << block
    end

    def after(&block)
      @after_procs << block
    end

    def commit(db)
      run(before_procs)

      loop do
        if observed_keys.any?
          db.watch(*observed_keys)
        end

        run(reading_procs)

        break if db.multi do
          run(writing_procs)
        end
      end

      run(after_procs)
    end

    def run(procs)
      procs.each { |p| p.call }
    end
  end
end