# Extend array with case equality to provide meaningful semantics in
# case statements.
#
# After this change, pattern matching-like behavior is possible with
# Arrays:
#
#     [Fixnum, String] === [1, "foo"]
#     [Symbol, Array] === [:foo, [1, 2]]
#
# The normal behavior is preserved:
#
#     [1, 2] === [1, 2]
#     [:foo, :bar] == [:foo, :bar]
#
# When used in a case statement, it provides a functionality close to that of
# languages with proper pattern matching. It becomes useful when implementing
# a polymorphic method:
#
#     def [](index, limit = nil)
#       case [index, limit]
#       when [Fixnum, Fixnum] then
#         key.lrange(index, limit).collect { |id| model[id] }
#       when [Range, nil] then
#         key.lrange(index.first, index.last).collect { |id| model[id] }
#       when [Fixnum, nil] then
#         model[key.lindex(index)]
#       end
#     end
#
# This extension is experimental and we will keep it under very close
# scrutinity. We acknowledge that patching a built-in data type is a bad
# practice.
class Array
  def ===(other)
    return false if size != other.size

    each_with_index do |item, index|
      return false unless item === other[index]
    end

    true
  end
end
