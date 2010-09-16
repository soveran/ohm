# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

require "ohm/utils/upgrade"

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

test "upgrade to hashes" do
  require "stringio"

  stderr, stdout = $stderr, $stdout

  $stderr, $stdout = StringIO.new, StringIO.new

  Ohm::Utils::Upgrade.new([:User]).run

  $stderr, $stdout = stderr, stdout

  @user = @users[1]

  assert redis.get(@user[:name]).nil?
  assert redis.get(@user[:email]).nil?
  assert redis.get(@user[:views]).nil?

  assert ["1", "2"] == redis.smembers(@user[:posts])

  assert [@users[:email][Ohm::Model.encode "albert-1@example.com"]] == redis.smembers(@user[:_indices])
  assert ["1"] == redis.smembers(@users[:email][Ohm::Model.encode "albert-1@example.com"])

  assert "Albert" == redis.hget(@user, :name)
  assert "albert-1@example.com" == redis.hget(@user, :email)
  assert "1" == redis.hget(@user, :views)
end
