# encoding: UTF-8

class Ohm < Thor
  desc "doc", "Generate YARD documentation"
  method_options :open => false
  def doc
    require "yard"

    opts = ["--protected", "--title", "Ohm – Object-hash mapping library for Redis"]

    YARD::CLI::Yardoc.run(*opts)

    system "open doc/index.html" if options[:open]
  end

  desc "deploy", "Deploy documentation"
  def deploy
    system "rsync -az doc/* ohm.keyvalue.org:deploys/ohm.keyvalue.org/"
  end

  desc "test", "Run all tests"
  def test
    invoke "ohm:redis:start"

    Dir["test/**/*_test.rb"].each do |file|
      load file
    end
  end

  class Redis < Thor
    desc "start", "Start Redis server"
    def start
      %x{dtach -n /tmp/ohm.dtach redis-server test/test.conf}
    end

    desc "attach", "Attach to Redis server"
    def attach
      %x{dtach -a /tmp/ohm.dtach}
    end
  end
end
