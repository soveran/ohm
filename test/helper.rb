$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__) + "/../lib"))

begin
  require "ruby-debug"
rescue LoadError
end

require "cutest"

def silence_warnings
  original_verbose, $VERBOSE = $VERBOSE, nil
  yield
ensure
  $VERBOSE = original_verbose
end

def assert_raise(type = Exception)
  begin
    yield
  rescue => ex
  ensure
    assert ex.kind_of?(type)
  end
end

class Logger
  def self.current
    Thread.current[:logger] ||= new
  end

  def initialize
    clear
  end

  def clear
    @lines = []
  end

  def debug(message)
    @lines << message.to_s
  end

  def debug?; true; end
  alias info  debug
  alias warn  debug
  alias error debug

  def commands
    @lines.map { |line| line[/Redis >> ([A-Z].+?)$/, 1] }.compact
  end
end

setup { }

$VERBOSE = true

require "ohm"
