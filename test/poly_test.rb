# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

require 'ohm/timestamps'

class ModelBase < Ohm::Model
  include Ohm::Timestamps
  self.base = self
end

class User < ModelBase
  attribute :name
  attribute :likes, Array
  attribute :age, Integer
  index :name
  set :following, User
  set :followers, User
  set :groups, Group
  index :followers
  index :groups
  index :likes
  counter :visits
  
  def validate
    assert_present :name
  end
  
  def follow(u)
    following << u
    u.followers << self
  end
end

class SuperUser < User
  attribute :kernel
  index :kernel

  def validate
    super
    assert_present :kernel
  end

end

class Hacker < SuperUser
  attribute :alias
  index :alias

  def validate
    super
    assert_present :alias
  end
  
end

module Power
  class User < ::User
    set :apps, String
  end
end

class Group < ModelBase
  collection :members, User
end

prepare do
  u = User.create( name: 'jo user', age: 33 )
  u2 = User.create( name: 'mari moe',age: 27 )
  @u3 = User.create( name: 'guruji', age: 77)
end

test "retrieving root type as root" do
  u = User.find( name: 'guruji' ).first
  assert User === u
end

test "add polymorphic followers" do
  @su = SuperUser.create( name: 'lenny', kernel: 'debian' )  
  User.all.each {|u|  u.follow(@u3) if u != @u3 }
  followers = @u3.followers.map(&:name).sort
  assert followers == ['jo user', 'lenny', 'mari moe']
  assert @u3.followers.map(&:class).sort == [SuperUser,User,User]
end

test "allow direct set assignment" do
  @su = SuperUser.create( name: 'lenny', kernel: 'debian' )  
  User.all.each {|u|  u.follow(@u3) if u != @u3 }
  u = User.create( name:'foo' )
  u.followers= @u3.followers.all
  assert u.followers.map(&:name).sort == ['jo user', 'lenny', 'mari moe']
end

test "create subclass" do
  @su = SuperUser.create( name: 'lenny', kernel: 'debian' )
end

test "root index includes subclasses in find" do
  @su = SuperUser.create( name: 'lenny', kernel: 'debian' )
  assert User.all.find( name: @su.name ).size == 1
  assert User.all.find( name: @su.name ).first.name == @su.name
end

test "find on mix of superclass and subclass inidces" do
  @su = SuperUser.create( name: 'lenny', kernel: 'debian' )
  assert SuperUser.all.find( name: @su.name, kernel: @su.kernel ).first
end

test "polymorphic find creates subclasses of proper type" do
  @su = SuperUser.create( name: 'lenny', kernel: 'debian' )
  assert SuperUser === User.all.find( name: @su.name ).first
end

test "namespaced derived class works normally" do
  @pu = Power::User.create( name: 'powner', age: 38 )
  assert Power::User === User.find( name: @pu.name ).first
end

test "id index returns subclasses" do
  @su = Hacker.create( name: 'lenny', kernel: 'debian', alias: 'condor' )
  assert Hacker === SuperUser[@su.id]
end

test "subclass id index doesn't return superclasses" do
  @su = SuperUser.create( name: 'lenny', kernel: 'debian' )
  assert Hacker[@su.id] == nil
end

test "promote type of existing object" do
  @su = Hacker.create( name: 'lenny', kernel: 'debian', alias: 'kvm' )
  assert Hacker === SuperUser[@su.id]
  SuperUser.create( id: @su.id )
  assert SuperUser == SuperUser[@su.id].class
  assert !Hacker.exists?(@su.id)
end

test "promote type of existing object with new/save" do
  @su = Hacker.create( name: 'lenny', kernel: 'debian', alias: 'kvm' )
  assert Hacker === SuperUser[@su.id]
  @su = User.new( SuperUser, id: @su.id )
  @su.save
  assert SuperUser == SuperUser[@su.id].class
  assert !Hacker.exists?(@su.id)
end
