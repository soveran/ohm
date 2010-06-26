# encoding: UTF-8

class OhmTasks < Thor
  namespace :ohm

  desc "doc", "Generate YARD documentation"
  method_options :open => false
  def doc
    require "yard"

    opts = ["--protected", "--title", "Ohm &mdash; Object-hash mapping library for Redis"]

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

    system "open doc/index.html" if options[:open]
  end

  desc "deploy", "Deploy documentation"
  def deploy
    system "rsync --del -avz doc/* ohm.keyvalue.org:deploys/ohm.keyvalue.org/"
  end
end
