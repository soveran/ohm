require File.dirname(__FILE__) + '/test_helper'

class IndicesTest < Test::Unit::TestCase
  class User < Ohm::Model
    attribute :email

    index [:email]
  end

  context "A model with an indexed attribute" do
    setup do
      $redis.flush_db

      @user1 = User.create(:email => "foo")
      @user2 = User.create(:email => "bar")
    end

    should "be able to find by the given attribute" do
      assert_equal [@user1], User.find(:email, "foo").to_a
    end

    should "update indices when changing attribute values" do
      @user1.email = "baz"
      @user1.save

      assert_equal [], User.find(:email, "foo").to_a
      assert_equal [@user1], User.find(:email, "baz").to_a
    end

    should "remove from the index after deleting" do
      @user2.delete

      assert_equal [], User.find(:email, "bar").to_a
    end
  end
end
