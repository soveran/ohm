# encoding: UTF-8

class OhmTasks < Thor
  namespace :ohm

  desc "doc", "Generate documentation"
  method_options :open => false
  def doc
    invoke :yard
    invoke :rocco

    system "open doc/index.html" if options[:open]
  end

  desc "yard", "Generate YARD documentation"
  def yard
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

  desc "rocco", "Generate ROCCO documentation"
  def rocco
    `mkdir doc/examples` unless Dir.exists?("doc/examples")
    `rocco examples/*.*`
    `mv examples/*.html doc/examples`
  end

  desc "deploy", "Deploy documentation"
  def deploy
    system "rsync --del -avz doc/* ohm.keyvalue.org:deploys/ohm.keyvalue.org/"
  end
end
