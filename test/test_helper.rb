$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__) + "/../lib"))

begin
  require "ruby-debug"
rescue LoadError
end

require "contest"
require "ohm"

Ohm.connect(:port => 6379, :db => 15, :timeout => 3)
Ohm.flush
