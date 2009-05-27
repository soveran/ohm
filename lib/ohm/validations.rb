module Ohm
  module Validations
    def valid?
      errors.clear
      validate
      errors.empty?
    end

    def validate
    end

    def errors
      @errors ||= []
    end

  protected

    def assert_format(att, format)
      if assert_present(att)
        assert send(att).match(format), [att, :format]
      end
    end

    def assert_present(att)
      if assert_not_nil(att)
        assert send(att).any?, [att, :empty]
      end
    end

    def assert_not_nil(att)
      assert send(att), [att, :nil]
    end

    def assert(value, error)
      value or errors.push(error) && false
    end
  end
end
