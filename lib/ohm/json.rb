require "json"

module Ohm
  class Model
    # Export a JSON representation of the model by encoding `to_hash`.
    def to_json(*args)
      to_hash.to_json(*args)
    end
  end

  module Collection
    # Sugar for to_a.to_json for all types of Sets
    def to_json(*args)
      to_a.to_json(*args)
    end
  end
end
