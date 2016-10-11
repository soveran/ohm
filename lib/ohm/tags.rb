=begin

Adds a `tags` attribute and a `tag` index, along with helper methods
for tagging and untagging model instances.

## Usage

    class Post < Ohm::Model
      include Tags
    end

    post = Post.create(tags: "foo bar")

    Post.find(tag: "foo").size #=> 1
    Post.find(tag: "bar").size #=> 1
    Post.find(tag: "baz").size #=> 0

    post.tag! "baz"

    Post.find(tag: "baz").size #=> 1

    post.untag! "foo"

    Post.find(tag: "foo").size #=> 1

=end
module Ohm
  module Tags
    def self.included(model)
      model.attribute :tags
      model.index :tag
    end

    def tag!(name)
      update(tags: (tag | [name]).join(' '))
    end

    def untag!(name)
      update(tags: (tag - [name]).join(' '))
    end

    def tag
      tags.to_s.split
    end
  end
end
