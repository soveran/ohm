Ohm ॐ
=====

Object-hash mapping library for Redis.

Description
-----------

Ohm is a library for storing objects in [Redis][redis], a persistent key-value
database. It includes an extensible list of validations and has very good
performance.

Community
---------

Join the mailing list: [http://groups.google.com/group/ohm-ruby](http://groups.google.com/group/ohm-ruby)

Meet us on IRC: [#ohm](irc://chat.freenode.net/#ohm) on [freenode.net](http://freenode.net/)


Related projects
----------------

These are libraries in other languages that were inspired by Ohm.

* [JOhm](https://github.com/xetorthio/johm) for Java, created by xetorthio
* [Lohm](https://github.com/slact/lua-ohm) for Lua, created by slact
* [Nohm](https://github.com/maritz/nohm) for Node.js, created by maritz
* [Redisco](https://github.com/iamteem/redisco) for Python, created by iamteem

Articles and Presentations
--------------------------

* [Simplicity](http://files.soveran.com/simplicity)
* [How to Redis](http://www.paperplanes.de/2009/10/30/how_to_redis.html)
* [Redis and Ohm](http://carlopecchia.eu/blog/2010/04/30/redis-and-ohm-part1/)
* [Ohm (Redis ORM)](http://blog.s21g.com/articles/1717) (Japanese)
* [Redis and Ohm](http://www.slideshare.net/awksedgreep/redis-and-ohm)
* [Ruby off Rails](http://www.slideshare.net/cyx.ucron/ruby-off-rails)

Getting started
---------------

Install [Redis][redis]. On most platforms it's as easy as grabbing the sources,
running make and then putting the `redis-server` binary in the PATH.

Once you have it installed, you can execute `redis-server` and it will
run on `localhost:6379` by default. Check the `redis.conf` file that comes
with the sources if you want to change some settings.

If you don't have Ohm, try this:

    $ [sudo] gem install ohm

Or you can grab the code from [http://github.com/soveran/ohm][ohm].

Now, in an irb session you can test the Redis adapter directly:

    >> require "ohm"
    => true
    >> Ohm.connect
    => []
    >> Ohm.redis.set "Foo", "Bar"
    => "OK"
    >> Ohm.redis.get "Foo"
    => "Bar"

## Connecting to the Redis database

There are a couple of different strategies for connecting to your Redis
database. The first is to explicitly set the `:host`, `:port`, `:db` and
`:timeout` options. You can also set only a few of them, and let the other
options fall back to the default.

The other noteworthy style of connecting is by just doing `Ohm.connect` and
set the environment variable `REDIS_URL`.

Here are the options for {Ohm.connect} in detail:

### :url (recommended)

A Redis URL of the form `redis://:<passwd>@<host>:<port>/<db>`.
Note that if you specify a URL and one of the other options at
the same time, the other options will take precedence. Also, if
you try and do `Ohm.connect` without any arguments, it will check
if `ENV["REDIS_URL"]` is set, and will use it as the argument for
`:url`.

### :host

Host where the Redis server is running, defaults to `"127.0.0.1"`.

### :port

Port number, defaults to `6379`.

### :db

Database number, defaults to `0`.

### :password

It is the secret that will be sent to the Redis server. Use it if the server
configuration requires it. Defaults to `nil`.

### :timeout

Database timeout in seconds, defaults to `0`.

### :thread_safe

Initializes the client with a monitor. It has a small performance penalty, and
it's off by default. For thread safety, it is recommended to use a different
instance per thread. I you have no choice, then pass `:thread_safe => true`
when connecting.

Models
------

Ohm's purpose in life is to map objects to a key value datastore. It
doesn't need migrations or external schema definitions. Take a look at
the example below:

### Example

```ruby
class Event < Ohm::Model
  attribute :name
  reference :venue, :Venue
  set :participants, :Person
  counter :votes

  index :name

  def validate
    assert_present :name
  end
end

class Venue < Ohm::Model
  attribute :name
  collection :events, :Event
end

class Person < Ohm::Model
  attribute :name
end
```

All models have the `id` attribute built in, you don't need to declare it.

This is how you interact with IDs:

```ruby
event = Event.create :name => "Ohm Worldwide Conference 2031"
event.id
# => 1

# Find an event by id
event == Event[1]
# => true

# Trying to find a non existent event
Event[2]
# => nil

# Finding all the events
Event.all
# => [#<Event @values={:id=>1, :name=>"Ohm Worldwide Conference 2031"}>]
```

This example shows some basic features, like attribute declarations and
validations. Keep reading to find out what you can do with models.

Attribute types
---------------

Ohm::Model provides four attribute types: {Ohm::Model.attribute
attribute}, {Ohm::Model.set set}, {Ohm::Model.list list}
and {Ohm::Model.counter counter}; and two meta types:
{Ohm::Model.reference reference} and {Ohm::Model.collection
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

```ruby
if event.valid?
  event.comments.add(Comment.create(:body => "Great event!"))
end
```

If you are saving the object, this will suffice:

```ruby
if event.save
  event.comments.add(Comment.create(:body => "Wonderful event!"))
end
```

Working with Sets
-----------------

Given the following model declaration:

```ruby
class Event < Ohm::Model
  attribute :name
  set :attendees, :Person
end
```

You can add instances of `Person` to the set of attendees with the
`add` method:

```ruby
event.attendees.add(Person.create(:name => "Albert"))

# And now...
event.attendees.each do |person|
  # ...do what you want with this person.
end
```

## Sorting

Since `attendees` is a {Ohm::Model::Set Set}, it exposes two sorting
methods: {Ohm::Model::Collection#sort sort} returns the elements
ordered by `id`, and {Ohm::Model::Collection#sort_by sort_by} receives
a parameter with an attribute name, which will determine the sorting
order. Both methods receive an options hash which is explained below:

### :order

Order direction and strategy. You can pass in any of the following:

1. ASC
2. ASC ALPHA (or ALPHA ASC)
3. DESC
4. DESC ALPHA (or ALPHA DESC)

It defaults to `ASC`.

__Important Note:__ Starting with Redis 2.6, `ASC` and `DESC` only
work with integers or floating point data types. If you need to sort
by an alphanumeric field, add the `ALPHA` keyword.

### :limit

The offset and limit from which we should start with. Note that
this is 0-indexed. It defaults to `0`.

Example:

`limit: [0, 10]` will get the first 10 entries starting from offset 0.

### :by

Key or Hash key with which to sort by. An important distinction with
using {Ohm::Model::Collection#sort sort} and
{Ohm::Model::Collection#sort_by sort_by} is that `sort_by` automatically
converts the passed argument with the assumption that it is a hash key
and it's within the current model you are sorting.

```ruby
Post.all.sort_by(:title)     # SORT Post:all BY Post:*->title
Post.all.sort(:by => :title) # SORT Post:all BY title
```

__Tip:__ Unless you absolutely know what you're doing, use `sort`
when you want to sort your models by their `id`, and use `sort_by`
otherwise.

### :get

A key pattern to return, e.g. `Post:*->title`. As is the case with
the `:by` option, using {Ohm::Model::Collection#sort sort} and
{Ohm::Model::Collection#sort_by sort_by} has distinct differences in
that `sort_by` does much of the hand-coding for you.

```ruby
Post.all.sort_by(:title, :get => :title)
# SORT Post:all BY Post:*->title GET Post:*->title

Post.all.sort(:by => :title, :get => :title)
# SORT Post:all BY title GET title
```


Associations
------------

Ohm lets you declare `references` and `collections` to represent associations.

```ruby
class Post < Ohm::Model
  attribute :title
  attribute :body
  collection :comments, :Comment
end

class Comment < Ohm::Model
  attribute :body
  reference :post, :Post
end
```

After this, every time you refer to `post.comments` you will be talking
about instances of the model `Comment`. If you want to get a list of IDs
you can use `post.comments.key.smembers`.

### References explained

Doing a {Ohm::Model.reference reference} is actually just a shortcut for
the following:

```ruby
# Redefining our model above
class Comment < Ohm::Model
  attribute :body
  attribute :post_id
  index :post_id

  def post=(post)
    self.post_id = post.id
  end

  def post
    Post[post_id]
  end
end
```

The only difference with the actual implementation is that the model
is memoized.

The net effect here is we can conveniently set and retrieve `Post` objects,
and also search comments using the `post_id` index.

```ruby
Comment.find(:post_id => 1)
```

### Collections explained

The reason a {Ohm::Model.reference reference} and a
{Ohm::Model.collection collection} go hand in hand, is that a collection is
just a macro that defines a finder for you, and we know that to find a model
by a field requires an {Ohm::Model.index index} to be defined for the field
you want to search.

```ruby
# Redefining our post above
class Post < Ohm::Model
  attribute :title
  attribute :body

  def comments
    Comment.find(:post_id => self.id)
  end
end
```

The only "magic" happening is with the inference of the `index` that was used
in the other model. The following all produce the same effect:

```ruby
# easiest, with the basic assumption that the index is `:post_id`
collection :comments, :Comment

# we can explicitly declare this as follows too:
collection :comments, :Comment, :post

# finally, we can use the default argument for the third parameter which
# is `to_reference`.
collection :comments, :Comment, to_reference

# exploring `to_reference` reveals a very interesting and simple concept:
Post.to_reference == :post
# => true
```

Indices
-------

An {Ohm::Model.index index} is a set that's handled automatically by Ohm. For
any index declared, Ohm maintains different sets of objects IDs for quick
lookups.

In the `Event` example, the index on the name attribute will
allow for searches like `Event.find(:name => "some value")`.

Note that the {Ohm::Model::Validations#assert_unique assert_unique}
validation and the methods {Ohm::Model::Set#find find} and
{Ohm::Model::Set#except except} need a corresponding index in order to work.

### Finding records

You can find a collection of records with the `find` method:

```ruby
# This returns a collection of users with the username "Albert"
User.find(:username => "Albert")
```

### Filtering results

```ruby
# Find all users from Argentina
User.find(:country => "Argentina")

# Find all activated users from Argentina
User.find(:country => "Argentina", :status => "activated")

# Find all users from Argentina, except those with a suspended account.
User.find(:country => "Argentina").except(:status => "suspended")

# Find all users both from Argentina and Uruguay
User.find(:country => "Argentina").union(:country => "Uruguay")
```

Note that calling these methods results in new sets being created
on the fly. This is important so that you can perform further operations
before reading the items to the client.

For more information, see [SINTERSTORE](http://redis.io/commands/sinterstore),
[SDIFFSTORE](http://redis.io/commands/sdiffstore) and
[SUNIONSTORE](http://redis.io/commands/sunionstore)

Uniques
-------

Uniques are similar to indices except that there can only be one record per
entry. The canonical example of course would be the email of your user, e.g.

```ruby
class User < Ohm::Model
  attribute :email
  unique :email
end

u = User.create(email: "foo@bar.com")
u == User.with(:email, "foo@bar.com")
# => true

User.create(email: "foo@bar.com")
# => raises Ohm::UniqueIndexViolation
```

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

```ruby
def assert(value, error)
  value or errors.push(error) && false
end
```

### assert_present

Checks that the given field is not nil or empty. The error code for this
assertion is `:not_present`.

```ruby
assert_present :name
```

### assert_format

Checks that the given field matches the provided format. The error code
for this assertion is :format.

```ruby
assert_format :username, /^\w+$/
```

### assert_numeric

Checks that the given field holds a number as a Fixnum or as a string
representation. The error code for this assertion is :not_numeric.

```ruby
assert_numeric :votes
```

### assert_url

Provides a pretty general URL regular expression match. An important
point to make is that this assumes that the URL should start with
`http://` or `https://`. The error code for this assertion is
`:not_url`.

### assert_email

In this current day and age, almost all web applications need to
validate an email address. This pretty much matches 99% of the emails
out there. The error code for this assertion is `:not_email`.

### assert_member

Checks that a given field is contained within a set of values (i.e.
like an `ENUM`).

``` ruby
def validate
  assert_member :state, %w{pending paid delivered}
end
```

The error code for this assertion is `:not_valid`

### assert_length

Checks that a given field's length falls under a specified range.

``` ruby
def validate
  assert_length :username, 3..20
end
```

The error code for this assertion is `:not_in_range`.

### assert_decimal

Checks that a given field looks like a number in the human sense
of the word. Valid numbers are: 0.1, .1, 1, 1.1, 3.14159, etc.

The error code for this assertion is `:not_decimal`.

Errors
------

When an assertion fails, the error report is added to the errors array.
Each error report contains two elements: the field where the assertion
was issued and the error code.

### Validation example

Given the following example:

```ruby
def validate
  assert_present :foo
  assert_numeric :bar
  assert_format :baz, /^\d{2}$/
end
```

If all the assertions fail, the following errors will be present:

```ruby
obj.errors
# => { foo: [:not_present], bar: [:not_numeric], baz: [:format] }
```

Ohm Extensions
==============

Ohm is rather small and can be extended in many ways.

A lot of amazing contributions are available at [Ohm Contrib][contrib]
make sure to check them if you need to extend Ohm's functionality.

[contrib]: http://cyx.github.com/ohm-contrib/

Upgrading
=========

The changes in Ohm 1 break the compatibility with previous versions.
We will do our best to provide a script to ease the pain of upgrading.
In the meantime, it's recommended that you use the new version only
for new projects.

[redis]: http://redis.io
[ohm]: http://github.com/soveran/ohm
