require "json"
require "redic"

module Stal
  #SHA = "4bd605bfee5f1e809089c5f98d10fab8aec38bd3"

  # Evaluate expression `expr` in the Redis client `c`.
  # Override #solve in order to use Redis-rb
  def self.solve(c, expr)
    begin
      opts = JSON.dump(expr)
      c.call!("EVALSHA", SHA, [], [opts])
    rescue RuntimeError
      if $!.message["NOSCRIPT"]
        #c.call!("SCRIPT", "FLUSH")
        c.call!("SCRIPT", "LOAD", File.read(LUA))
        opts = JSON.dump(expr)
        c.call!("EVALSHA", SHA, [], [opts])
      else
        raise $!
      end
    end
  end
end

