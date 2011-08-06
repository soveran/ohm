Polymorphism
=====

Polymorphism allows Ohm models to be derived from, subclassed and specialized. Subclasses of an Ohm model may add attributes, collections and indices to the root model. When the root is queried using `find`, a polymorphic collection of subclasses of the root class is returned.

### Example

    class User < Ohm::Model
      attribute :name
      index :name
    end

    class SuperUser < User
      attribute :kernel
      index :kernel
    end

Here `SuperUser` derives from `User` and adds the indexed attribute `kernel`.

## Model Root 

All models that have subclasses are deemed polymorphic. The model `root` is the superclass of all its polymorphs. The `roots` are your application classes that derive from `Ohm::Model`:

    >> User.root
    => User
    >> SuperUser.root
    => User

    >> User.create( name:'jojo' )
    => #<User:1 name="jojo">
    >> SuperUser.create( name:'lenny', kernel:'debian' )
    => #<SuperUser:2 name="lenny" kernel="debian">
    
The `all` collection for the model root contains all subclasses of the root:

    >> User.all.map(&:name)
    => ["jojo", "lenny"]
    >> User.all.map(&:class)
    => [User, SuperUser]

Whereas the subclass `all` collections contain only objects of that subclass:

    >> SuperUser.all.map(&:name)
    => ["lenny"]

In effect, we persist a hidden `_type` attribute with all subclass instances, and `Subclass.all` is the name of the index on `_type`.

## Finding Subclasses

When you perform a `find`, you specify the model `root` or the first descendant that has all of the indices that you are searching on:

    >> User.find( name:'lenny' ).first
    => #<SuperUser:2 name="lenny" kernel="debian">
    >> SuperUser.find( kernel:'debian' ).first
    => #<SuperUser:2 name="lenny" kernel="debian">
    
    >> User.find( kernel:'centos' )
    => Ohm::Model::IndexNotFound  # error    

## Setting the Base Class

What if your model roots derive from a common application base class, `ModelBase`, rather than `Ohm::Model`? You set the base class like this:

    class ModelBase < Ohm::Model
      self.base = self
    end
    
    class User < ModelBase; ... end
    class SuperUser < User; ... end
    

Typecasts
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

Serializers
-----

The new `Serialized` module uses `Serializers` to convert primitive values to `String`s for writing to the database, and back to objects when read. `Serializers` are defined for all the basic attribute types, including `Integer`, `Float`, `Decimal`, `Boolean`, `Date`, `Time`, `Hash`, and `Array`.

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
    
