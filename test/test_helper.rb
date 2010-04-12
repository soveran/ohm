require "rubygems"

begin
  require "ruby-debug"
rescue LoadError
end

require "contest"
require File.dirname(__FILE__) + "/../lib/ohm"

Ohm.connect(:port => 6379, :db => 15, :timeout => 3)
Ohm.flush
