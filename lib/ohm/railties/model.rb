module Ohm
  class Model

    def persisted?
      !new?
    end

    def to_param
      @id unless new?
    end

    def to_key
      [@id] unless new?
    end

    def _destroy
      false
    end

    # def to_model
    #   self
    # end

    def model_name
      self.class.model_name
    end

    def self.model_name
      @_model_name ||= ActiveModel::Name.new(self)
    end

  end
end
