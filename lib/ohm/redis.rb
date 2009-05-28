require 'socket'
require 'set'

begin
  if (RUBY_VERSION >= '1.9')
    require 'timeout'
    RedisTimer = Timeout
  else
    require 'system_timer'
    RedisTimer = SystemTimer
  end
rescue LoadError
  RedisTimer = nil
end

class Redis
  BulkCommands = {
    "set"=>true, "setnx"=>true, "rpush"=>true, "lpush"=>true,
    "lset"=>true, "lrem"=>true, "sadd"=>true, "srem"=>true,
    "sismember"=>true, "echo"=>true, "getset"=>true, "smove"=>true
  }

  ConvertToBool = lambda { |reply| reply == 0 ? false : reply }

  ReplyProcessor = {
    "exists" => ConvertToBool,
    "sismember"=> ConvertToBool,
    "sadd"=> ConvertToBool,
    "srem"=> ConvertToBool,
    "smove"=> ConvertToBool,
    "move"=> ConvertToBool,
    "setnx"=> ConvertToBool,
    "del"=> ConvertToBool,
    "renamenx"=> ConvertToBool,
    "expire"=> ConvertToBool,
    "keys" => lambda { |reply| reply.split(" ") },
    "info" => lambda { |reply|
      info = Hash.new
      reply.each_line do |line|
        key, value = line.split(":", 2).map { |part| part.chomp }
        info[key.to_sym] = value
      end
      info
    }
  }

  Aliases = {
    "flush_db" => "flushdb",
    "flush_all" => "flushall",
    "last_save" => "lastsave",
    "key?" => "exists",
    "delete" => "del",
    "randkey" => "randomkey",
    "list_length" => "llen",
    "push_tail" => "rpush",
    "push_head" => "lpush",
    "pop_tail" => "rpop",
    "pop_head" => "lpop",
    "list_set" => "lset",
    "list_range" => "lrange",
    "list_trim" => "ltrim",
    "list_index" => "lindex",
    "list_rm" => "lrem",
    "set_add" => "sadd",
    "set_delete" => "srem",
    "set_count" => "scard",
    "set_member?" => "sismember",
    "set_members" => "smembers",
    "set_intersect" => "sinter",
    "set_intersect_store" => "sinterstore",
    "set_inter_store" => "sinterstore",
    "set_union" => "sunion",
    "set_union_store" => "sunionstore",
    "set_diff" => "sdiff",
    "set_diff_store" => "sdiffstore",
    "set_move" => "smove",
    "set_unless_exists" => "setnx",
    "rename_unless_exists" => "renamenx",
    "type?" => "type"
  }

  # Add a default proc to return the key as a value for misses.
  Aliases.send(:initialize, &(lambda { |hash, key| hash[key] = key }))

  def initialize(opts={})
    @host = opts[:host] || '127.0.0.1'
    @port = opts[:port] || 6379
    @db = opts[:db] || 0
    @timeout = opts[:timeout] || 0
    connect_to_server
  end

  def to_s
    "Redis Client connected to #{@host}:#{@port} against DB #{@db}"
  end

  def connect_to_server
    connect_to(@host, @port, @timeout == 0 ? nil : @timeout)
    call_command(["select", @db]) if @db != 0
  end

  def connect_to(host, port, timeout = nil)

    # We support connect() timeout only if system_timer is availabe or
    # if we are running against Ruby >= 1.9. Timeout reading from the
    # socket instead will be supported anyway.
    if @timeout != 0 and RedisTimer
      begin
        @sock = TCPSocket.new(host, port, 0)
      rescue Timeout::Error
        @sock = nil
        raise Timeout::Error, "Timeout connecting to the server"
      end
    else
      @sock = TCPSocket.new(host, port, 0)
    end
    @sock.setsockopt Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1

    # If the timeout is set we configure the low level socket options in
    # order to make sure a blocking read will return after the specified
    # number of seconds. This hack is from the Memcached Ruby client.
    if timeout
      secs = Integer(timeout)
      usecs = Integer((timeout - secs) * 1_000_000)
      optval = [secs, usecs].pack("l_2")
      @sock.setsockopt Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, optval
      @sock.setsockopt Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, optval
    end
  end

  def method_missing(*argv)
    call_command(argv)
  end

  def connected?
    !! @sock
  end

  def call_command(argv)

    # This wrapper to raw_call_command handle reconnection on socket
    # error. We try to reconnect just one time, otherwise let the error
    # araise.
    connect_to_server unless connected?
    begin
      raw_call_command(argv)
    rescue Errno::ECONNRESET
      @sock.close
      connect_to_server
      raw_call_command(argv)
    end
  end

  def raw_call_command(argv)
    bulk = nil
    argv[0] = Aliases[argv[0].to_s.downcase]
    if BulkCommands[argv[0]] and argv.length > 1
      bulk = argv[-1].to_s
      argv[-1] = bulk.length
    end
    @sock.write(argv.join(" ") + "\r\n")
    @sock.write(bulk + "\r\n") if bulk

    # Post process the reply if needed
    processor = ReplyProcessor[argv[0]]
    processor ? processor.call(read_reply) : read_reply
  end

  def [](key)
    get(key)
  end

  def []=(key, value)
    set(key, value)
  end

  def list(key)
    lrange(key, 0, -1)
  end

  def sort(key, opts = {})
    cmd = []
    cmd << "SORT #{key}"
    cmd << "BY #{opts[:by]}" if opts[:by]
    cmd << "GET #{[opts[:get]].flatten * ' GET '}" if opts[:get]
    cmd << "#{opts[:order]}" if opts[:order]
    cmd << "LIMIT #{opts[:limit].join(' ')}" if opts[:limit]
    call_command(cmd)
  end

  def incr(key, increment = nil)
    call_command(increment ? ["incrby", key, increment] :  ["incr", key])
  end

  def decr(key, decrement = nil)
    call_command(decrement ? ["decrby", key, decrement] :  ["decr", key])
  end

  def read_reply

    # We read the first byte using read() mainly because gets() is
    # immune to raw socket timeouts.
    begin
      reply_type = @sock.read(1)
    rescue Errno::EAGAIN

      # We want to make sure it reconnects on the next command after the
      # timeout. Otherwise the server may reply in the meantime leaving
      # the protocol in a desync status.
      @sock = nil
      raise Errno::EAGAIN, "Timeout reading from the socket"
    end

    raise Errno::ECONNRESET,"Connection lost" unless reply_type

    line = @sock.gets

    case reply_type

    # Error reply
    when "-"
      raise "-" + line.strip

    # Status code reply
    when "+"
      line.strip

    # Integer reply
    when ":"
      line.to_i

    # Bulk reply
    when "$"
      bulklen = line.to_i
      return nil if bulklen == -1
      reply = @sock.read(bulklen)
      @sock.read(2) # Discard CRLF.
      reply

    # Multi bulk reply
    when "*"
      objects = line.to_i
      return nil if bulklen == -1
      reply = []
      objects.times { reply << read_reply }
      reply
    else
      raise "Protocol error, got '#{reply_type}' as initial reply byte"
    end
  end
end
