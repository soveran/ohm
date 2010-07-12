require File.expand_path("test_helper", File.dirname(__FILE__))

class Post < Ohm::Model
  attribute :title

  list :categories, Category
end

class Category < Ohm::Model
  attribute :name

  set :posts, Post
end

class CircularReferenceTest < Test::Unit::TestCase
  setup do
    @post = Post.create(:title => "New post")
    @category = Category.create(:name => "Ruby")
  end

  test "inspect" do
    @post.categories << @category
    @category.posts << @post

    assert_equal %Q{#<Post:1 title="New post" categories=#<List (Category): ["1"]>>}, @post.inspect
    assert_equal %Q{#<Category:1 name="Ruby" posts=#<Set (Post): ["1"]>>}, @category.inspect
  end
end
