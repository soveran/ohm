class <%= class_name %><%= " < #{options[:parent].classify}" if options[:parent] %> < Ohm::Model
<% attributes.reject{|attr| attr.reference?}.each do |attribute| -%>
  attribute :<%= attribute.name %> <%= attribute.type_class %>
<% end -%>
end
