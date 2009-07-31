Ohm ॐ
=====

Object-hash mapping library for Redis.

Description
-----------

Ohm is a library that allows to store an object in
[Redis](http://code.google.com/p/redis/), a persistent key-value
database. It includes an extensible list of validations and has very
good performance.


Getting started
---------------

Install [Redis](http://code.google.com/p/redis/). On most platforms
it's as easy as grabbing the sources, running make and then putting the
`redis-server` binary in the PATH.

Once you have it installed, you can execute `redis-server` and it will
run on `localhost:6379` by default. Check the `redis.conf` file that comes
with the sources if you want to change some settings.

If you don't have Ohm, try this:

    $ sudo gem install ohm

Now, in an irb session try this:

    >> require "ohm"
    => true
    >> Ohm.connect
    => []
    >> Ohm.redis.set "Foo", "Bar"
    => "OK"
    >> Ohm.redis.get "Foo"
    => "Bar"

Models
------

Ohm::Model is an object-hash mapper that persists its attributes in a
Redis datastore.

### Example

    class Event < Ohm::Model
      attribute :name
      set :participants
      list :comments
      counter :votes

      index :name

      def validate
        assert_present :name
      end
    end

    event = Event.create(:name => "Ruby Tuesday")
    event.participants << "Michel Martens"
    event.participants << "Damian Janowski"
    event.participants.all #=> ["Damian Janowski", "Michel Martens"]

    event.comments << "Very interesting event!"
    event.comments << "Agree"
    event.comments.all #=> ["Very interesting event!", "Agree"]

    another_event = Event.new
    another_event.valid?    #=> false
    another_event.errors    #=> [[:name, :nil]]

    another_event.name = ""
    another_event.valid?    #=> false
    another_event.errors    #=> [[:name, :empty]]

    another_event.name = "Ruby Lunch"
    another_event.create    #=> true

    event.incr(:votes)      #=> 1
    event.incr(:votes)      #=> 2
    event.decr(:votes)      #=> 1

This example shows some basic features, like attribute declarations and
validations.

Attribute types
---------------

Ohm::Model provides four attribute types: `attribute`, `set`, `list` and
`counter`.

### attribute

An `attribute` is just any value that can be stored as a string. In the
example above, we used this field to store the Event's `name`. You can
use it to store numbers, but be aware that Redis will return a string
when you retrieve the value.

### set

A `set` in Redis is an unordered list, with an external behavior similar
to that of Ruby arrays, but optimized for faster membership lookups.
It's used internaly by Ohm to keep track of the instances of each model
and for generating and maintaining indexes.

### list

A `list` is like an array in Ruby. It's perfectly suited for queues and
for keeping elements in order.

### counter

A `counter` is like a regular attribute, but the direct manipulation
of the value is not allowed. You can retrieve, increase or decrease
the value, but you can not assign it. In the example above, we used a
counter attribute for tracking votes. As the incr and decr operations
are atomic, you can rest assured a vote won't be counted twice.

Indexes
-------

An index is a set that's handled automatically by Ohm. For any index declared,
Ohm maintains different sets of objects ids for quick lookups.

For example, in the example above, the index on the name attribute will
allow for searches like Event.find(:name, "some value").

You can also declare an index on multiple colums, like this:

    index [:name, :company]

Note that the `find` method and the `assert_unique` validation need a
corresponding index to exist.

Validations
-----------

Before every save, the `validate` method is called by Ohm. In the method definition
you can use assertions that will determine if the attributes are valid.

### Assertions

#### assert

The `assert` method is used by all the other assertions. It pushes the
second parameter to the list of errors if the first parameter evaluates
to false.

    def assert(value, error)
      value or errors.push(error) && false
    end

#### assert_present

Checks that the given field is not nil or empty. The error code for this
assertion is :not_present.

#### assert_format

Checks that the given field matches the provided format. The error code
for this assertion is :format.

#### assert_numeric

Checks that the given field holds a number as a Fixnum or as a string
representation. The error code for this assertion is :not_numeric.

#### assert_unique

Validates that the attribute or array of attributes are unique.
For this, an index of the same kind must exist. The error code is
:not_unique.


Errors
------

When an assertion fails, the error report is added to the errors array.
Each error report contains two elements: the field where the assertion
was issued and the error code.

### Validation example

Given the following example:

    def validate
      assert_present :foo
      assert_numeric :bar
      assert_format :baz, /^\d{2}$/
      assert_unique :qux
    end

If the validation fails, the following errors will be present:

    obj.errors #=> [[:foo, :not_present], [:bar, :not_numeric], [:baz, :format], [[:qux], :not_unique]]

Note that the error for assert_unique wraps the field in an array.
The purpose for this is to standardize the format for both single and
multicolumn indexes.
