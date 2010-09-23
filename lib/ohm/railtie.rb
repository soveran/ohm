#
#
# Rails Candy
#
#
# String.class_eval do
#   def partial_path
#     self.downcase.pluralize << '/' << self.downcase.singular
#   end
# end
String.send(:alias_method, :plural, :pluralize)
String.send(:alias_method, :singular, :singularize)

module Ohm
  class Model


    def to_param;        id;      end
    def to_model;        self;    end
    def self.model_name; self.to_s.downcase; end
    def to_key;          [self.model_name];  end

  end
end
