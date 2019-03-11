Gem::Specification.new do |s|
  s.name = "ohm"
  s.version = "3.1.1"
  s.summary = %{Object-hash mapping library for Redis.}
  s.description = %Q{Ohm is a library that allows to store an object in Redis, a persistent key-value database. It has very good performance.}
  s.authors = ["Michel Martens", "Damian Janowski", "Cyril David"]
  s.email = ["michel@soveran.com", "djanowski@dimaion.com", "me@cyrildavid.com"]
  s.homepage = "http://soveran.github.io/ohm/"
  s.license = "MIT"

  s.files = `git ls-files`.split("\n")

  s.rubyforge_project = "ohm"

  s.add_dependency "redic-rb", "1.6.1"

  s.add_development_dependency "cutest"
  s.add_development_dependency "spirit_hands", "~> 2.1"
end

