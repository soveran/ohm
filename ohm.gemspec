Gem::Specification.new do |s|
  s.name = 'ohm'
  s.version = '0.0.4'
  s.summary = %{Object-hash mapping library for Redis.}
  s.date = %q{2009-03-13}
  s.author = "Michel Martens, Damian Janowski"
  s.email = "michel@soveran.com"
  s.homepage = "http://github.com/soveran/ohm"

  s.specification_version = 2 if s.respond_to? :specification_version=

  s.files = ["lib/ohm/redis.rb", "lib/ohm/validations.rb", "lib/ohm.rb", "README.markdown", "LICENSE", "Rakefile", "test/all_tests.rb", "test/benchmarks.rb", "test/db/dump.rdb", "test/db/redis.pid", "test/indices_test.rb", "test/model_test.rb", "test/redis_test.rb", "test/test.conf", "test/test_helper.rb", "test/validations_test.rb"]

  s.require_paths = ['lib']

  s.has_rdoc = false
end
