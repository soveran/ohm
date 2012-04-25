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

  Cutest.run(Dir["test/*.rb"])
end

desc "Generate documentation"
task :doc => :yard

desc "Generated YARD documentation"
task :yard do
  require "yard"

  opts = []
  opts.push("--protected")
  opts.push("--no-private")
  opts.push("--private")
  opts.push("--title", "Ohm &mdash; Object-hash mapping library for Redis")

  YARD::CLI::Yardoc.run(*opts)

  Dir["doc/**/*.html"].each do |file|
    contents = File.read(file)

    contents.sub! %r{</body>}, <<-EOS
      <script type="text/javascript">
      var gaJsHost = (("https:" == document.location.protocol) ? "https://ssl." : "http://www.");
      document.write(unescape("%3Cscript src='" + gaJsHost + "google-analytics.com/ga.js' type='text/javascript'%3E%3C/script%3E"));
      </script>
      <script type="text/javascript">
      try {
      var pageTracker = _gat._getTracker("UA-11356145-1");
      pageTracker._trackPageview();
      } catch(err) {}</script>
      </body>
    EOS

    File.open(file, "w") { |f| f.write(contents) }
  end
end

desc "Deploy documentation"
task :deploy do
  system "rsync --del -avz doc/* ohm.keyvalue.org:deploys/ohm.keyvalue.org/"
end
