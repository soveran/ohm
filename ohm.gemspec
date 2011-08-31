
Gem::Specification.new do |s|
  s.name = "ohm"
  s.version = "0.2.0"
  s.summary = %{Object-hash mapping library for Redis.}
  s.description = %Q{Ohm is a library that allows to store an object in Redis, a persistent key-value database. It includes an extensible list of validations and has very good performance.}
  s.authors = ["Michel Martens", "Damian Janowski", "tribalvibes"]
  s.email = ["michel@soveran.com", "djanowski@dimaion.com", "tribalvibes@tribalvibes.com"]
  s.homepage = "http://github.com/soveran/ohm"
  s.files = ["lib/ohm/callbacks.rb", "lib/ohm/compat-1.8.6.rb", "lib/ohm/helpers.rb", "lib/ohm/key.rb", "lib/ohm/pattern.rb", "lib/ohm/search.rb", "lib/ohm/serialized.rb", "lib/ohm/timestamps.rb", "lib/ohm/utils/upgrade.rb", "lib/ohm/validations.rb", "lib/ohm/version.rb", "lib/ohm.rb", "README.markdown", "LICENSE", "Rakefile", "test/1.8.6_test.rb", "test/associations_test.rb", "test/connection_test.rb", "test/errors_test.rb", "test/hash_key_test.rb", "test/helper.rb", "test/indices_test.rb", "test/json_test.rb", "test/model_test.rb", "test/mutex_test.rb", "test/pattern_test.rb", "test/poly_test.rb", "test/serialized_test_.rb", "test/upgrade_script_test.rb", "test/validations_test.rb", "test/wrapper_test.rb", "test/test.conf"]
  s.rubyforge_project = "ohm"
  s.add_dependency "nest", "~> 1.0"
  s.add_development_dependency "cutest", "~> 0.1"
  s.add_development_dependency "batch", "~> 0.0.1"
end
