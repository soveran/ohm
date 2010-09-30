require "rake/testtask"

REDIS_DIR = File.expand_path(File.join("..", "test"), __FILE__)
REDIS_CNF = File.join(REDIS_DIR, "test.conf")
REDIS_PID = File.join(REDIS_DIR, "db", "redis.pid")

task :default => :run

desc "Run tests and manage server start/stop"
task :run => [:start, :test, :stop]

desc "Start the Redis server"
task :start do
  unless File.exists?(REDIS_PID)
    system "redis-server #{REDIS_CNF}"
  end
end

desc "Stop the Redis server"
task :stop do
  if File.exists?(REDIS_PID)
    system "kill #{File.read(REDIS_PID)}"
    File.delete(REDIS_PID)
  end
end

task :test do
  require File.expand_path("./test/helper", File.dirname(__FILE__))

  Cutest.run(Dir["test/*_test.rb"])
end

namespace :examples do
  desc "Run all the examples"
  task :run do
    begin
      require "cutest"
    rescue LoadError
      raise "!! Missing gem `cutest`. Try `gem install cutest`."
    end

    Cutest.run(Dir["examples/*.rb"])
  end
end

