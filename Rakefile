require "rake/testtask"

task :default => :test

desc 'Run all tests'
Rake::TestTask.new(:test) do |t|
  t.pattern = 'test/**/*_test.rb'
  t.verbose = false
end
