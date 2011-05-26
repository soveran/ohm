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

`Typecast` from Ohm-contrib is now part of the core. Model `attribute` declarations accept a type (class) name:

    require 'ohm/typecast'
    class User < Ohm::Model
      include Ohm::Typecast
      attribute :name   # String
      attribute :score, Integer
      attribute :last_login, Time
    end

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
    
