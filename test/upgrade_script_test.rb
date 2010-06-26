# encoding: UTF-8

require File.join(File.dirname(__FILE__), "test_helper")

require "ohm/utils/upgrade"

# class User < Ohm::Model
#   attribute :name
#   attribute :email
#
#   counter :views
#
#   index :email
#
#   set :posts
#   list :comments
# end

class UpgradeScriptTest < Test::Unit::TestCase
  def redis
    Ohm.redis
  end

  setup do
    redis.flushdb

    @users = Ohm::Key.new(:User, Ohm.redis)

    10.times do
      @id = redis.incr(@users[:id])
      @user = @users[@id]

      redis.sadd @users[:all], @id

      redis.set  @user[:name], "Albert"
      redis.set  @user[:email], "albert-#{@id}@example.com"
      redis.incr @user[:views]

      redis.sadd @user[:posts], 1
      redis.sadd @user[:posts], 2

      redis.lpush @user[:comments], 3
      redis.lpush @user[:comments], 4

      redis.sadd @user[:_indices], @users[:email][Ohm::Model.encode "albert-#{@id}@example.com"]
      redis.sadd @users[:email][Ohm::Model.encode "albert-#{@id}@example.com"], @id
    end
  end

  should "upgrade to hashes" do
    Ohm::Utils::Upgrade.new([:User]).run

    @user = @users[1]

    assert_nil redis.get(@user[:name])
    assert_nil redis.get(@user[:email])
    assert_nil redis.get(@user[:views])

    assert_equal ["1", "2"], redis.smembers(@user[:posts])

    assert_equal [@users[:email][Ohm::Model.encode "albert-1@example.com"]], redis.smembers(@user[:_indices])
    assert_equal ["1"], redis.smembers(@users[:email][Ohm::Model.encode "albert-1@example.com"])

    assert_equal "Albert", redis.hget(@user, :name)
    assert_equal "albert-1@example.com", redis.hget(@user, :email)
    assert_equal "1", redis.hget(@user, :views)
  end
end
