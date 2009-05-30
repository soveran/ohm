require "rubygems"

begin
  require "ruby-debug"
rescue LoadError
end

require "contest"
require File.dirname(__FILE__) + "/../lib/ohm"

$redis = Redis.new(:port => 6381)
$redis.flush_db
