Gem::Specification.new do |s|
  s.name = "ohm"
  s.version = "2.3.0"
  s.summary = %{Object-hash mapping library for Redis.}
  s.description = %Q{Ohm is a library that allows to store an object in Redis, a persistent key-value database. It has very good performance.}
  s.authors = ["Michel Martens", "Damian Janowski", "Cyril David"]
  s.email = ["michel@soveran.com", "djanowski@dimaion.com", "me@cyrildavid.com"]
  s.homepage = "http://soveran.github.io/ohm/"
  s.license = "MIT"

  s.files = `git ls-files`.split("\n")

  s.rubyforge_project = "ohm"

  s.add_dependency "redic", "~> 1.5.0"
  s.add_dependency "nido"
  s.add_dependency "stal"
  s.add_dependency "msgpack", "~> 0.5"

  s.add_development_dependency "cutest"
end
