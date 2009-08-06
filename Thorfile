class Ohm < Thor
  desc "doc", "Generate YARD documentation"
  method_options :open => false
  def doc
    require "yard"

    opts = ["--protected", "--title", "Ohm – Object-hash mapping library for Redis"]

    YARD::CLI::Yardoc.run(*opts)

    system "open doc/index.html" if options[:open]
  end

  desc "deploy", "Generate and deploy documentation"
  def deploy
    doc
    system "rsync -az doc/* ohm.keyvalue.org:deploys/ohm.keyvalue.org/"
  end

  desc "test", "Run all tests"
  def test
    Dir["test/**/*_test.rb"].each do |file|
      load file
    end
  end
end
