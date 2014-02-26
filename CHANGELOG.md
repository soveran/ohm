## 2.0.0.rc2

- Lists now respond to range.

  Example:

  ```ruby
  class Comment < Ohm::Model
  end

  class Post < Ohm::Model
    list :comments, :Comment
  end

  c1 = Comment.create
  c2 = Comment.create
  c3 = Comment.create

  post = Post.create
  post.comments.push(c1)
  post.comments.push(c2)
  post.comments.push(c3)

  post.comments.range(0, 1) == [c1, c2]
  # => true
  ```

- When a record is created, `#id` returns a string instead of an integer.
  This ensures ID is string everywhere:

  Example:

  ```ruby

  # Before
  Meetup.create(name: "Ruby").id # => 1
  Meetup.with(:name, "Ruby").id  # => "1"

  # Now
  Meetup.create(name: "Ruby").id # => "1"
  Meetup.with(:name, "Ruby").id  # => "1"
  ```

- If an attribute is set to an empty string, Ohm won't delete it.

  Example:

  ```ruby
  # Before
  event = Meetup.create(location: "")
  Meetup[event.id].location # => nil

  # Now
  event = Meetup.create(location: "")
  Meetup[event.id].location # => ""
  ```

- Include `Ohm::List#ids` in the public API. It returns an array with all
  the ID's in the list.

  Example:

  ```ruby
  class Comment < Ohm::Model
  end

  class Post < Ohm::Model
    list :comments, :Comment
  end

  post = Post.create
  post.comments.push(Comment.create)
  post.comments.push(Comment.create)
  post.comments.push(Comment.create)

  post.comments.ids
  # => ["1", "2", "3"]
  ```

- Include `Ohm::BasicSet#exists?` in the public API. This makes possible
  to check if an id is included in a set. Check `Ohm::BasicSet#exists?`
  documentation for more details.

  Example:

  ```ruby
  class Post < Ohm::Model
  end

  class User < Ohm::Model
    set :posts, :Post
  end

  user = User.create
  user.posts.add(post = Post.create)

  user.posts.exists?(post.id)       # => true
  user.posts.exists?("nonexistent") # => false
  ```

- Change `Ohm::MultiSet#except` to union keys instead of intersect them
  when passing an array.

  Example:

  ```ruby
  class User < Ohm::Model
    attribute :name
  end

  john = User.create(name: "John")
  jane = User.create(name: "Jane")

  res = User.all.except(name: [john.name, jane.name])

  # Before
  res.size # => 2

  # Now
  res.size # => 0
  ```

- Move ID generation to Lua. With this change, it's no longer possible
  to generate custom ids. All ids are autoincremented.

- Add `Ohm::Model.track` method to allow track of custom keys. This key
  is removed when the model is deleted.

  Example:

  ```ruby
  class Foo < Ohm::Model
    track :notes
  end

  foo = Foo.create

  Foo.redis.call("SET", foo.key[:notes], "something")
  Foo.redis.call("GET", "Foo:1:notes")
  # => "something"

  foo.delete
  Foo.redis.call("GET", "Foo:1:notes")
  # => nil
  ```

- `Ohm::Model#reference` accepts strings as model references.

  Example:

  ```ruby
  class Bar < Ohm::Model
    reference :foo, "SomeNamespace::Foo"
  end

  Bar.create.foo.class # => SomeNamespace::Foo
  ```

- `Ohm::Model#save` sanitizes attributes before sending them to Lua.
  This complies with the original spec in Ohm v1 where a `to_s`
  is done on each value.

  Example:

  ```ruby
  class Post < Ohm::Model
    attribute :published
  end

  post = Post.create(published: true)
  post = Post[post.id]

  # Before
  post.published # => "1"

  # Now
  post.published # => "true"
  ```

- `Ohm::Model#save` don't save values for attributes set to false.

  Example:

  ```ruby
  class Post < Ohm::Model
    attribute :published
  end

  post = Post.create(published: false)
  post = Post[post.id]

  # Before
  post.published # => "0"

  # Now
  post.published # => nil
  ```

- `nest` dependency has been removed. Now, Ohm uses [nido][nido]
  to generate the keys that hold the data.

- `scrivener` dependency has been removed. Ohm no longer supports model
  validations and favors filter validation on the boundary layer. Check
  [scrivener][scrivener] project for more information.

- `redis` dependency has been removed. Ohm 2 uses [redic][redic],
  a lightweight Redis client. Redic uses the `hiredis` gem for the
  connection and for parsing the replies. Now, it defaults to a
  Redic connection to "redis://127.0.0.1:6379". To change it, you
  will need to provide an instance of `Redic` through the `Ohm.redis=`
  helper.

  Example:

  ```ruby
  Ohm.redis = Redic.new("redis://:<passwd>@<host>:<port>/<db>")
  ```

  Check the Redic README for more details.

- `Ohm::Model#transaction` and `Ohm::Transaction` have been removed.

- Move `save` and `delete` operations to Lua scripts.

- Support for Ruby 1.8 and 1.9 has been removed.

[nido]: https://github.com/soveran/nido
[scrivener]: https://github.com/soveran/scrivener
[redic]: https://github.com/amakawa/redic

## 1.3.2

- Fetching a batch of objects is now done in batches of 1000 objects at
  a time. If you are iterating over large collections, this change should
  provide a significant performance boost both in used memory and total
  execution time.

- `MutableSet#&lt;&lt;` is now an alias for `#add`.

## 1.3.1

- Improve memory consumption when indexing persisted attributes.
  No migration is needed and old indices will be cleaned up as you save
  instances.

## 1.3.0

- Add Model.attributes.

## 1.2.0

- Enumerable fix.

- Merge Ohm::PipelinedFetch into Ohm::Collection.

- Fix Set, MultiSet, and List enumerable behavior.

- Change dependencies to use latest cutest.

## 1.1.0

- Compatible with redis-rb 3.

## 1.0.0

- Fetching a batch of objects is now done through one pipeline, effectively
  reducing the IO to just 2 operations (one for SMEMBERS / LRANGE, one for
  the actual HGET of all the individual HASHes.)

- write_remote / read_remote have been replaced with set / get respectively.

- Ohm::Model.unique has been added.

- Ohm::Model::Set has been renamed to Ohm::Set

- Ohm::Model::List has been renamed to Ohm::List

- Ohm::Model::Collection is gone.

- Ohm::Validations is gone. Ohm now uses Scrivener::Validations.

- Ohm::Key is gone. Ohm now uses Nest directly.

- No more concept of volatile keys.

- Ohm::Model::Wrapper is gone.

- Use Symbols for constants instead of relying on Ohm::Model.const_missing.

- #sort / #sort_by now uses `limit` as it's used in redis-rb, e.g. you
  have to pass in an array like so: sort(limit: [0, 1]).

- Set / List have been trimmed to contain only the minimum number
  of necessary methods.

- You can no longer mutate a collection / set as before, e.g. doing
  User.find(...).add(User[1]) will throw an error.

- The #union operation has been added. You can now chain it with your filters.

- Temporary keys when doing finds are now automatically cleaned up.

- Counters are now stored in their own key instead, i.e. in
  User:<id>:counters.

- JSON support has to be explicitly required by doing `require
  "ohm/json"`.

- All save / delete / update operations are now done using
  transactions (see http://redis.io/topics/transactions).

- All indices are now stored without converting the values to base64.
