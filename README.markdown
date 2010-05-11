Ohm ॐ
=====

Object-hash mapping library for Redis.

Description
-----------

Ohm is a library for storing objects in
[Redis](http://code.google.com/p/redis/), a persistent key-value
database. It includes an extensible list of validations and has very
good performance.

Community
---------

Join the mailing list: [http://groups.google.com/group/ohm-ruby](http://groups.google.com/group/ohm-ruby)

Meet us on IRC: [#ohm](irc://chat.freenode.net/#ohm) on [freenode.net](http://freenode.net/)

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

Or you can grab the code from [http://github.com/soveran/ohm](http://github.com/soveran/ohm).

Now, in an irb session you can test the Redis adapter directly:

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

Ohm's purpose in life is to map objects to a key value datastore. It
doesn't need migrations or external schema definitions. Take a look at
the example below:

### Example

    class Event < Ohm::Model
      attribute :name
      reference :venue, Venue
      set :participants, Person
      counter :votes

      index :name

      def validate
        assert_present :name
      end
    end

    class Venue < Ohm::Model
      attribute :name
      collection :events, Event
    end

    class Person < Ohm::Model
      attribute :name
    end

All models have the `id` attribute built in, you don't need to declare it.

This is how you interact with IDs:

    event = Event.create :name => "Ohm Worldwide Conference 2031"
    event.id
    # => 1

    # Find an event by id
    event == Event[1]
    # => true

    # Trying to find a non existent event
    Event[2]
    # => nil

This example shows some basic features, like attribute declarations and
validations. Keep reading to find out what you can do with models.

Attribute types
---------------

Ohm::Model provides four attribute types: {Ohm::Model::attribute
attribute}, {Ohm::Model::set set}, {Ohm::Model::list list}
and {Ohm::Model::counter counter}; and two meta types:
{Ohm::Model::reference reference} and {Ohm::Model::collection
collection}.

### attribute

An `attribute` is just any value that can be stored as a string. In the
example above, we used this field to store the event's `name`. You can
use it to store numbers, but be aware that Redis will return a string
when you retrieve the value.

### set

A `set` in Redis is an unordered list, with an external behavior similar
to that of Ruby arrays, but optimized for faster membership lookups.
It's used internally by Ohm to keep track of the instances of each model
and for generating and maintaining indexes.

### list

A `list` is like an array in Ruby. It's perfectly suited for queues
and for keeping elements in order.

### counter

A `counter` is like a regular attribute, but the direct manipulation
of the value is not allowed. You can retrieve, increase or decrease
the value, but you can not assign it. In the example above, we used a
counter attribute for tracking votes. As the incr and decr operations
are atomic, you can rest assured a vote won't be counted twice.

### reference

It's a special kind of attribute that references another model.
Internally, Ohm will keep a pointer to the model (its ID), but you get
accessors that give you real instances. You can think of it as the model
containing the foreign key to another model.

### collection

Provides an accessor to search for all models that `reference` the current model.

Persistence strategy
--------------------

The attributes declared with `attribute` are only persisted after
calling `save`. If the object is in an invalid state, no value is sent
to Redis (see the section on **Validations** below).

Operations on attributes of type `list`, `set` and `counter` are
possible only after the object is created (when it has an assigned
`id`). Any operation on these kinds of attributes is performed
immediately, without running the object validations. This design yields
better performance than running the validations on each operation or
buffering the operations and waiting for a call to `save`.

For most use cases, this pattern doesn't represent a problem.
If you need to check for validity before operating on lists, sets or
counters, you can use this pattern:

    if event.valid?
      event.comments << "Great event!"
    end

If you are saving the object, this will suffice:

    if event.save
      event.comments << "Wonderful event!"
    end

Working with Sets
-----------------

Given the following model declaration:

    class Event < Ohm::Model
      attribute :name
      set :attendees, Person
    end

You can add instances of `Person` to the set of attendees with the
`<<` method:

    @event.attendees << Person.create(name: "Albert")

    # And now...
    @event.attendees.each do |person|
      # ...do what you want with this person.
    end

Sorting
-------

Since `attendees` is a {Ohm::Model::Set Set}, it exposes two sorting
methods: {Ohm::Model::Collection#sort sort} returns the elements
ordered by `id`, and {Ohm::Model::Collection#sort_by sort_by} receives
a parameter with an attribute name, which will determine the sorting
order. Both methods receive an options hash which is explained in the
documentation for {Ohm::Model::Collection#sort sort}.

Associations
------------

Ohm lets you declare `references` and `collections` to represent associations.

    class Post < Ohm::Model
      attribute :title
      attribute :body
      collection :comments, Comment
    end

    class Comment < Ohm::Model
      attribute :body
      reference :post, Post
    end

After this, every time you refer to `post.comments` you will be talking
about instances of the model `Comment`. If you want to get a list of IDs
you can use `post.comments.raw`.

Indexes
-------

An index is a set that's handled automatically by Ohm. For any index declared,
Ohm maintains different sets of objects IDs for quick lookups.

In the `Event` example, the index on the name attribute will
allow for searches like `Event.find(:name => "some value")`.

Note that the `assert_unique` validation and the methods `find` and `except` need a
corresponding index in order to work.

### Finding records

You can find a collection of records with the `find` method:

    # This returns a collection of users with the username "Albert"
    User.find(:username => "Albert")

### Filtering results

    # Find all users from Argentina
    User.find(:country => "Argentina")

    # Find all activated users from Argentina
    User.find(:country => "Argentina", :status => "activated")

    # Find all users from Argentina, except those with a suspended account.
    User.find(:country => "Argentina").except(:status => "suspended")

Note that calling these methods results in new sets being created
on the fly. This is important so that you can perform further operations
before reading the items to the client.

For more information, see [SINTERSTORE](http://code.google.com/p/redis/wiki/SinterstoreCommand) and [SDIFFSTORE](http://code.google.com/p/redis/wiki/SdiffstoreCommand).

Validations
-----------

Before every save, the `validate` method is called by Ohm. In the method
definition you can use assertions that will determine if the attributes
are valid. Nesting assertions is a good practice, and you are also
encouraged to create your own assertions. You can trigger validations at
any point by calling `valid?` on a model instance.

Assertions
-----------

Ohm ships with some basic assertions. Check Ohm::Validations to see
the method definitions.

### assert

The `assert` method is used by all the other assertions. It pushes the
second parameter to the list of errors if the first parameter evaluates
to false.

    def assert(value, error)
      value or errors.push(error) && false
    end

### assert_present

Checks that the given field is not nil or empty. The error code for this
assertion is :not_present.

    assert_present :name

### assert_format

Checks that the given field matches the provided format. The error code
for this assertion is :format.

    assert_format :username, /^\w+$/

### assert_numeric

Checks that the given field holds a number as a Fixnum or as a string
representation. The error code for this assertion is :not_numeric.

    assert_numeric :votes

### assert_unique

Validates that the attribute or array of attributes are unique.
For this, an index of the same kind must exist. The error code is :not_unique.

    assert_unique :email

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

If all the assertions fail, the following errors will be present:

    obj.errors
    # => [[:foo, :not_present], [:bar, :not_numeric], [:baz, :format], [:qux, :not_unique]]

Presenting errors
-----------------

Unlike other ORMs, that define the full error messages in the model
itself, Ohm encourages you to define the error messages outside. If
you are using Ohm in the context of a web framework, the views are the
proper place to write the error messages.

Ohm provides a presenter that helps you in this quest. The basic usage
is as follows:

    error_messages = @model.errors.present do |e|
      e.on [:name, :not_present], "Name must be present"
      e.on [:account, :not_present], "You must supply an account"
    end

    error_messages
    # => ["Name must be present", "You must supply an account"]

Having the error message definitions in the views means you can use any
sort of helpers. You can also use blocks instead of strings for the
values. The result of the block is used as the error message:

    error_messages = @model.errors.present do |e|
      e.on [:email, :not_unique] do
        "The email #{@model.email} is already registered."
      end
    end

    error_messages
    # => ["The email foo@example.com is already registered."]

Versions
========

Ohm uses features from Redis > 1.3.10. If you are stuck in previous
versions, please use Ohm 0.0.35 instead.

Upgrading from 0.0.x to 0.1
---------------------------

Since Ohm 0.1 changes the persistence strategy (from 1-key-per-attribute
to Hashes), you'll need to run a script to upgrade your old data set.
Fortunately, it is built in:

    require "ohm/utils/upgrade"

    Ohm.connect :port => 6380

    Ohm::Utils::Upgrade.new([:User, :Post, :Comment]).run

Yes, you need to provide the model names. The good part is that you
don't have to load your application environment. Since we assume it's
very likely that you have a bunch of data, the script uses
[Batch](http://github.com/djanowski/batch) to show you some progress
while the process runs.
