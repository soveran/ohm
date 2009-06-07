require File.join(File.dirname(__FILE__), "test_helper")

class IndicesTest < Test::Unit::TestCase
  class User < Ohm::Model
    attribute :email

    index :email
  end

  context "A model with an indexed attribute" do
    setup do
      Ohm.redis.flushdb

      @user1 = User.create(:email => "foo")
      @user2 = User.create(:email => "bar")
    end

    should "be able to find by the given attribute" do
      assert_equal [@user1], User.find(:email, "foo")
    end

    should "update indices when changing attribute values" do
      @user1.email = "baz"
      @user1.save

      assert_equal [], User.find(:email, "foo")
      assert_equal [@user1], User.find(:email, "baz")
    end

    should "remove from the index after deleting" do
      @user2.delete

      assert_equal [], User.find(:email, "bar")
    end
  end
end
