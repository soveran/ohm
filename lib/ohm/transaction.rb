module Ohm

  # Transactions in Ohm are designed to be composable and atomic. They use
  # Redis WATCH/MULTI/EXEC to perform the comands sequentially but in a single
  # step.
  #
  # @example
  #
  #   redis = Ohm.redis
  #
  #   t1 = Ohm::Transaction.new do |t|
  #     s = nil
  #
  #     t.watch("foo")
  #
  #     t.read do
  #       s = redis.type("foo")
  #     end
  #
  #     t.write do
  #       redis.set("foo", s)
  #     end
  #   end
  #
  #   t2 = Ohm::Transaction.new do |t|
  #     t.watch("foo")
  #
  #     t.write do
  #       redis.set("foo", "bar")
  #     end
  #   end
  #
  #   # Compose transactions by passing them to Ohm::Transaction.new.
  #   t3 = Ohm::Transaction.new(t1, t2)
  #   t3.commit(redis)
  #
  #   # Compose transactions by appending them.
  #   t1.append(t2)
  #   t1.commit(redis)
  #
  # @see http://redis.io/topic/transactions Transactions in Redis.
  class Transaction
    class Store
      class EntryAlreadyExistsError < RuntimeError
      end

      class NoEntryError < RuntimeError
      end

      def initialize
        @dict = Hash.new
      end

      def [](key)
        raise NoEntryError unless @dict.member?(key)

        @dict[key]
      end

      def []=(key, value)
        raise EntryAlreadyExistsError if @dict.member?(key)

        @dict[key] = value
      end
    end

    attr :phase

    def initialize
      @phase = Hash.new { |h, k| h[k] = Array.new }

      yield self if block_given?
    end

    def append(t)
      t.phase.each do |key, values|
        phase[key].concat(values - phase[key])
      end

      self
    end

    def watch(*keys)
      phase[:watch].concat(keys - phase[:watch])
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
      phase[:before].each(&:call)

      loop do
        store = Store.new

        if phase[:watch].any?
          db.watch(*phase[:watch])
        end

        run(phase[:read], store)

        break if db.multi do
          run(phase[:write], store)
        end

        store = nil
      end

      phase[:after].each(&:call)
    end

    def run(procs, store)
      procs.each { |p| p.call(store) }
    end
  end

  def self.transaction(&block)
    Transaction.new(&block)
  end
end
