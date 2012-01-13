# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

class Person < Ohm::Model
  attribute :name
end

class ::Note < Ohm::Model
  attribute :content
  reference :source, Post
  collection :comments, Comment
  list :ratings, Rating
end

class ::Comment < Ohm::Model
  reference :note, Note
end

class ::Rating < Ohm::Model
  attribute :value
end

class ::Editor < Ohm::Model
  attribute :name
  reference :post, Post
end

class ::Post < Ohm::Model
  reference :author, Person
  collection :notes, Note, :source
  collection :editors, Editor
end

setup do
  @post = Post.create
end

test "return an instance of Person if author_id has a valid id" do
  @post.author_id = Person.create(:name => "Albert").id
  @post.save
  assert "Albert" == Post[@post.id].author.name
end

test "assign author_id if author is sent a valid instance" do
  @post.author = Person.create(:name => "Albert")
  @post.save
  assert "Albert" == Post[@post.id].author.name
end

test "assign nil if nil is passed to author" do
  @post.author = nil
  @post.save
  assert Post[@post.id].author.nil?
end

test "be cached in an instance variable" do
  @author = Person.create(:name => "Albert")
  @post.update(:author => @author)

  assert @author == @post.author
  assert @post.author.object_id == @post.author.object_id

  @post.update(:author => Person.create(:name => "Bertrand"))

  assert_equal "Bertrand", @post.author.name
  assert_equal @post.author.object_id, @post.author.object_id

  @post.update(:author_id => Person.create(:name => "Charles").id)

  assert_equal "Charles", @post.author.name
end

setup do
  @post = Post.create
  @note = Note.create(:content => "Interesting stuff", :source => @post)
  @comment = Comment.create(:note => @note)
end

test "return a set of notes" do
  assert @note.source == @post
  assert @note == @post.notes.first
end

test "return a set of comments" do
  assert @comment == @note.comments.first
end

test "return a list of ratings" do
  @rating = Rating.create(:value => 5)
  @note.ratings << @rating

  assert @rating == @note.ratings.first
end

test "default to the current class name" do
  @editor = Editor.create(:name => "Albert", :post => @post)

  assert @editor == @post.editors.first
end
