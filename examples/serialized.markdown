Typecast
------

`Typecast` from Ohm-contrib is deprecated in favor of `Serialized` which is now part of the core.

Serialized
-----

`Serialized` is the new module name for typed attributes. It should be mostly source compatible with `Typecast`, but unlike that approach, it avoids the use of proxies for the values.

With `Serialized`, model `attribute` declarations accept a type (class) name:

    require 'ohm/serialized'
    class User < Ohm::Model
      include Ohm::Serialized
      attribute :name   # String
      attribute :score, Integer
      attribute :last_login, Time
      attribute :opts, Hash
    end

Attribute values are serialized from the declared type to String on assignment, and converted back when the attribute is read. The serialization happens using a `Serializer` based on the declared attribute type.

Often it's nice to have a default value for an attribute rather than `nil`, such as an empty hash `{}` for a `Hash` attribute. This can be accomplished with the `default: value` option on the attribute declaration, which is then passed through to the serializer.

    attribute :opts, Hash, default: {}

You can also pass a `Proc`, e.g.:

    attribute :time, Time, default: -> { Time.now }

The default proc will be passed the current object and the attribute name if its arity allows, i.e.:

    attribute :meta, Hash, default: {|obj,att| obj[att] = { this: att } }

Serializers
-----

The new `Serialized` module uses `Serializers` to convert primitive values to `String`s for writing to the database, and back to objects when read. `Serializers` are defined for all the basic attribute types, including `Integer`, `Float`, `Decimal`, `Boolean`, `Symbol`, `Date`, `Time`, `Hash`, and `Array`.

The `HashSerializer` and `ArraySerializer` use `JSON` to represent their values as `String`.  This has inherent limitations as sub-objects of these structures are not presently deserialized to objects, but only primitive values. It's easy to define another serialization mechanism, however. See the source for examples.

`HashSerializer` by default symbolizes its keys on deserialization. To change this for an attribute, use the `symbolize_keys: false` option when declaring the attribute:

    attribute :names, Hash, symbolize_keys: false

The default serializers can be overriden or a custom serializer provided for an attribute with the `serializer:` option when declaring the attribute:

    attribute :start, Time, serializer: MyCustomTimeSerializer

If you define a custom serializer for your own class or to override a default serializer, when you name your serializer either `<Class>::Serializer` or `<Class>Serializer` then you won't need to specify it with the `serializer:` option.

Timestamps
------

`Timestamps` is adapted to the core from Ohm-contrib and now persists Time values preserving microseconds:

    require 'ohm/timestamps'
    class Order < Ohm::Model
      include Ohm::Timestamps
      # defines:
      #   attribute :created_at, Timestamp
      #   attribute :updated_at, Timestamp
    end
    
    >> Order.create
    => #<Order:1 created_at="2011-05-26 09:10:40.921490 UTC" updated_at="2011-05-26 09:10:40.921490 UTC">
    
