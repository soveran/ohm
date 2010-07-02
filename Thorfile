# encoding: UTF-8

class OhmTasks < Thor
  namespace :ohm

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
end
