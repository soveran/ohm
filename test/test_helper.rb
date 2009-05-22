require "rubygems"
require "ruby-debug"
require "contest"
require File.dirname(__FILE__) + "/../lib/ohm"

$redis = Redis.new(:port => 6381)
$redis.flush_db
