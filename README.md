Ohm ॐ
=====

Object-hash mapping library for Redis.

Description
-----------

Ohm is a library for storing objects in [Redis][redis], a persistent key-value
database. It has very good performance.

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

    $ [sudo] gem install ohm -v 2.0.0.rc1

Or you can grab the code from [http://github.com/soveran/ohm][ohm].

Now, in an irb session you can test the Redis adapter directly:

    >> require "ohm"
    => true
    >> Ohm.redis.call "SET", "Foo", "Bar"
    => "OK"
    >> Ohm.redis.call "GET", "Foo"
    => "Bar"

Note that the install instructions from above are for our release candidate, *not* for the current rubygems release (which is 1.3.2). If you want to use the current rubygems release just do a


    $ [sudo] gem install ohm

and from then on follow the instructions for [this release](https://github.com/soveran/ohm/tree/1.3.2/README.md).

## Connecting to a Redis database

Ohm uses a lightweight Redis client called [Redic][redic]. To connect
to a Redis database, you will need to set an instance of `Redic`, with
an URL of the form `redis://:<passwd>@<host>:<port>/<db>`, through the
`Ohm.redis=` method, e.g.

```ruby
require "ohm"

Ohm.redis = Redic.new("redis://127.0.0.1:6379")

Ohm.redis.call "SET", "Foo", "Bar"

Ohm.redis.call "GET", "Foo"
# => "Bar"
```

Ohm defaults to a Redic connection to "redis://127.0.0.1:6379". The
example above could be rewritten as:

```ruby
require "ohm"

Ohm.redis.call "SET", "Foo", "Bar"

Ohm.redis.call "GET", "Foo"
# => "Bar"
```

All Ohm models inherit the same connection settings from `Ohm.redis`.
For cases where certain models need to connect to different databases,
they simple have to override that, i.e.

```ruby
require "ohm"

Ohm.redis = Redic.new(ENV["REDIS_URL1"])

class User < Ohm::Model
end

User.redis = Redic.new(ENV["REDIS_URL2"])
```

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
Event.all.to_a
# => [<Event:1 name='Ohm Worldwide Conference 2031'>]
```

This example shows some basic features, like attribute declarations and
querying. Keep reading to find out what you can do with models.

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
calling `save`.

Operations on attributes of type `list`, `set` and `counter` are
possible only after the object is created (when it has an assigned
`id`). Any operation on these kinds of attributes is performed
immediately. This design yields better performance than buffering
the operations and waiting for a call to `save`.

For most use cases, this pattern doesn't represent a problem.
If you are saving the object, this will suffice:

```ruby
if event.save
  event.comments.add(Comment.create(body: "Wonderful event!"))
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
event.attendees.add(Person.create(name: "Albert"))

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
Post.all.sort(by: :title) # SORT Post:all BY title
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
Post.all.sort_by(:title, get: :title)
# SORT Post:all BY Post:*->title GET Post:*->title

Post.all.sort(by: :title, get: :title)
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
you can use `post.comments.ids`.

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
Comment.find(post_id: 1)
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
    Comment.find(post_id: self.id)
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
allow for searches like `Event.find(name: "some value")`.

Note that the methods {Ohm::Model::Set#find find} and
{Ohm::Model::Set#except except} need a corresponding index in order to work.

### Finding records

You can find a collection of records with the `find` method:

```ruby
# This returns a collection of users with the username "Albert"
User.find(username: "Albert")
```

### Filtering results

```ruby
# Find all users from Argentina
User.find(country: "Argentina")

# Find all activated users from Argentina
User.find(country: "Argentina", status: "activated")

# Find all users from Argentina, except those with a suspended account.
User.find(country: "Argentina").except(status: "suspended")

# Find all users both from Argentina and Uruguay
User.find(country: "Argentina").union(country: "Uruguay")
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

Ohm Extensions
==============

Ohm is rather small and can be extended in many ways.

A lot of amazing contributions are available at [Ohm Contrib][contrib]
make sure to check them if you need to extend Ohm's functionality.

[contrib]: http://cyx.github.com/ohm-contrib/

Upgrading
=========

Ohm 2 breaks the compatibility with previous versions. If you're upgrading an
existing application, it's nice to have a good test coverage before going in.
To know about fixes and changes, please refer to the CHANGELOG file.

[redis]: http://redis.io
[ohm]: http://github.com/soveran/ohm
[redic]: https://github.com/amakawa/redic
