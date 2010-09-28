# encoding: UTF-8

module Ohm
  # Provides a base implementation for extensible validation routines.
  # {Ohm::Validations} currently only provides the following assertions:
  #
  # * assert
  # * assert_present
  # * assert_format
  # * assert_numeric
  #
  # The core tenets that Ohm::Validations advocates can be summed up in a
  # few bullet points:
  #
  # 1. Validations are much simpler and better done using composition rather
  #    than macros.
  # 2. Error messages should be kept separate and possibly in the view or
  #    presenter layer.
  # 3. It should be easy to write your own validation routine.
  #
  # Since Ohm's philosophy is to keep the core code small, other validations
  # are simply added on a per-model or per-project basis.
  #
  # If you want other validations you may want to take a peek at Ohm::Contrib
  # and all of the validation modules it provides.
  #
  # @see http://cyx.github.com/ohm-contrib/doc/Ohm/WebValidations.html
  # @see http://cyx.github.com/ohm-contrib/doc/Ohm/NumberValidations.html
  # @see http://cyx.github.com/ohm-contrib/doc/Ohm/ExtraValidations.html
  #
  # @example
  #
  #   class Product < Ohm::Model
  #     attribute :title
  #     attribute :price
  #     attribute :date
  #
  #     def validate
  #       assert_present :title
  #       assert_numeric :price
  #       assert_format  :date, /\A[\d]{4}-[\d]{1,2}-[\d]{1,2}\z
  #     end
  #   end
  #
  #   product = Product.new
  #   product.valid? == false
  #   # => true
  #
  #   product.errors == [[:title, :not_present], [:price, :not_numeric],
  #                      [:date, :format]]
  #   # => true
  #
  module Validations
    # Provides a simple implementation using the Presenter Pattern. When
    # presenting errors, you have to properly catch all errors generated, or
    # else you'll get an {Ohm::Validations::Presenter::UnhandledErrors}
    # exception.
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

    # A simple class for storing all errors. Since {Ohm::Validations::Errors}
    # extends Array, you can expect all array methods to work on it.
    class Errors < Array
      attr_accessor :model

      def initialize(model)
        @model = model
      end

      def present(presenter = Presenter, &block)
        presenter.new(model.errors).present(&block)
      end
    end

    # Check if the current model state is valid. Each call to {#valid?} will
    # reset the {#errors} array.
    #
    # All model validations should be declared in a `validate` method.
    #
    # @example
    #
    #   class Post < Ohm::Model
    #     attribute :title
    #
    #     def validate
    #       assert_present :title
    #     end
    #   end
    #
    def valid?
      errors.clear
      validate
      errors.empty?
    end

    # Base validate implementation.
    def validate
    end

    # All errors for this model.
    def errors
      @errors ||= Errors.new(self)
    end

  protected

    # Allows you to do a validation check against a regular expression.
    # It's important to note that this internally calls {#assert_present},
    # therefore you need not structure your regular expression to check
    # for a non-empty value.
    #
    # @param [Symbol] att The attribute you want to verify the format of.
    # @param [Regexp] format The regular expression with which to compare
    #                 the value of att with.
    # @param [Array<Symbol, Symbol>] error The error that should be returned
    #                                when the validation fails.
    def assert_format(att, format, error = [att, :format])
      if assert_present(att, error)
        assert(send(att).to_s.match(format), error)
      end
    end

    # The most basic and highly useful assertion. Simply checks if the
    # value of the attribute is empty.
    #
    # @param [Symbol] att The attribute you wish to verify the presence of.
    # @param [Array<Symbol, Symbol>] error The error that should be returned
    #                                when the validation fails.
    def assert_present(att, error = [att, :not_present])
      assert(!send(att).to_s.empty?, error)
    end

    # Checks if all the characters of an attribute is a digit. If you want to
    # verify that a value is a decimal, try looking at Ohm::Contrib's
    # assert_decimal assertion.
    #
    # @param [Symbol] att The attribute you wish to verify the numeric format.
    # @param [Array<Symbol, Symbol>] error The error that should be returned
    #                                when the validation fails.
    # @see http://cyx.github.com/ohm-contrib/doc/Ohm/NumberValidations.html
    def assert_numeric(att, error = [att, :not_numeric])
      if assert_present(att, error)
        assert_format(att, /^\d+$/, error)
      end
    end

    # The grand daddy of all assertions. If you want to build custom
    # assertions, or even quick and dirty ones, you can simply use this method.
    #
    # @example
    #
    #   class Post < Ohm::Model
    #     attribute :slug
    #     attribute :votes
    #
    #     def validate
    #       assert_slug :slug
    #       assert votes.to_i > 0, [:votes, :not_valid]
    #     end
    #
    #   protected
    #     def assert_slug(att, error = [att, :not_slug])
    #       assert send(att).to_s =~ /\A[a-z\-0-9]+\z/, error
    #     end
    #   end
    def assert(value, error)
      value or errors.push(error) && false
    end
  end
end

