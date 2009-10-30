Gem::Specification.new do |s|
  s.name = 'ohm'
  s.version = '0.0.26'
  s.summary = %{Object-hash mapping library for Redis.}
  s.description = %Q{Ohm is a library that allows to store an object in Redis, a persistent key-value database. It includes an extensible list of validations and has very good performance.}
  s.authors = ["Michel Martens", "Damian Janowski"]
  s.email = ["michel@soveran.com", "djanowski@dimaion.com"]
  s.homepage = "http://github.com/soveran/ohm"
  s.files = ["lib/ohm/redis.rb", "lib/ohm/validations.rb", "lib/ohm.rb", "README.markdown", "LICENSE", "Rakefile", "Thorfile", "test/all_tests.rb", "test/benchmarks.rb", "test/connection_test.rb", "test/errors_test.rb", "test/indices_test.rb", "test/model_test.rb", "test/mutex_test.rb", "test/redis_test.rb", "test/search_test.rb", "test/test_helper.rb", "test/validations_test.rb", "test/test.conf"]
  s.rubyforge_project = "ohm"
end
