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

module Rails
end
