Gem::Specification.new do |s|
  s.name = "ohm"
  s.version = "1.0.0.rc4"
  s.summary = %{Object-hash mapping library for Redis.}
  s.description = %Q{Ohm is a library that allows to store an object in Redis, a persistent key-value database. It includes an extensible list of validations and has very good performance.}
  s.authors = ["Michel Martens", "Damian Janowski"]
  s.email = ["michel@soveran.com", "djanowski@dimaion.com"]
  s.homepage = "http://github.com/soveran/ohm"

  s.files = Dir[
    "lib/**/*.rb",
    "README*",
    "LICENSE",
    "Rakefile",
    "test/**/*.rb",
    "test/test.conf"
  ]

  s.rubyforge_project = "ohm"
  s.add_dependency "nest", "~> 1.0"
  s.add_dependency "scrivener", "~> 0.0.3"
  s.add_development_dependency "cutest", "~> 0.1"
  s.add_development_dependency "batch", "~> 0.0.1"
end
