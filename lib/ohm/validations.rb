module Ohm
  module Validations
    class Presenter
      class UnhandledErrors < StandardError
        attr :errors

        def initialize(errors)
          @errors = errors
        end

        def message
          "Unhandled errors: #{errors.inspect}"
        end
      end

      def initialize(errors)
        @errors = errors
        @unhandled = errors.dup
        @output = []
      end

      def on(error, message = (block_given? ? yield : raise(ArgumentError)))
        handle(error) do
          @output << message
        end
      end

      def ignore(error)
        handle(error)
      end

      def present
        yield(self)
        raise UnhandledErrors.new(@unhandled) unless @unhandled.empty?
        @output
      end

    protected

      def handle(error)
        if (errors = @errors.select {|e| error === e }).any?
          @unhandled -= errors
          yield(errors) if block_given?
        end
      end
    end

    class Errors < Array
      attr_accessor :model

      def initialize(model)
        @model = model
      end

      def present(presenter = Presenter, &block)
        presenter.new(model.errors).present(&block)
      end
    end

    def valid?
      errors.clear
      validate
      errors.empty?
    end

    def validate
    end

    def errors
      @errors ||= Errors.new(self)
    end

  protected

    def assert_format(att, format, error = [att, :format])
      if assert_present(att, error)
        assert(send(att).to_s.match(format), error)
      end
    end

    def assert_present(att, error = [att, :not_present])
      assert(send(att).to_s.any?, error)
    end

    def assert_numeric(att, error = [att, :not_numeric])
      if assert_not_nil(att)
        assert_format(att, /^\d+$/, error)
      end
    end

    def assert_not_nil(att, error = [att, :nil])
      assert(send(att), error)
    end

    def assert(value, error)
      value or errors.push(error) && false
    end
  end
end
