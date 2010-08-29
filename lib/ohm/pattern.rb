# Pattern extends Array with case equality to provide meaningful semantics in
# case statements.
#
# After this change, pattern matching-like behavior is possible with
# Arrays:
#
#     Pattern[Fixnum, String] === [1, "foo"]
#     Pattern[Symbol, Array] === [:foo, [1, 2]]
#
# When used in a case statement, it provides a functionality close to that of
# languages with proper pattern matching. It becomes useful when implementing
# a polymorphic method:
#
#     def [](index, limit = nil)
#       case [index, limit]
#       when Pattern[Fixnum, Fixnum] then
#         key.lrange(index, limit).collect { |id| model[id] }
#       when Pattern[Range, nil] then
#         key.lrange(index.first, index.last).collect { |id| model[id] }
#       when Pattern[Fixnum, nil] then
#         model[key.lindex(index)]
#       end
#     end
#
module Ohm
  class Pattern < Array
    def ===(other)
      return false if size != other.size

      each_with_index do |item, index|
        return false unless item === other[index]
      end

      true
    end
  end
end
