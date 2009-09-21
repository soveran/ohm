require 'socket'

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

module Ohm
  class Redis
    class ProtocolError < RuntimeError
      def initialize(reply_type)
        super("Protocol error, got '#{reply_type}' as initial reply byte")
      end
    end

    BulkCommands = {
      :set => true,
      :setnx => true,
      :rpush => true,
      :lpush => true,
      :lset => true,
      :lrem => true,
      :sadd => true,
      :srem => true,
      :sismember => true,
      :echo => true,
      :getset => true,
      :smove => true
    }

    ProcessorIdentity = lambda { |reply| reply }
    ProcessorConvertToBool = lambda { |reply| reply == 0 ? false : reply }
    ProcessorSplitKeys = lambda { |reply| reply.split(" ") }
    ProcessorInfo = lambda do |reply|
      info = Hash.new
      reply.each_line do |line|
        key, value = line.split(":", 2).map { |part| part.chomp }
        info[key.to_sym] = value
      end
      info
    end

    ReplyProcessor = {
      :exists => ProcessorConvertToBool,
      :sismember=> ProcessorConvertToBool,
      :sadd=> ProcessorConvertToBool,
      :srem=> ProcessorConvertToBool,
      :smove=> ProcessorConvertToBool,
      :move=> ProcessorConvertToBool,
      :setnx=> ProcessorConvertToBool,
      :del=> ProcessorConvertToBool,
      :renamenx=> ProcessorConvertToBool,
      :expire=> ProcessorConvertToBool,
      :keys => ProcessorSplitKeys,
      :info => ProcessorInfo
    }

    ReplyProcessor.send(:initialize) do |hash, key|
      hash[key] = ProcessorIdentity
    end

    def initialize(opts={})
      @host = opts[:host] || '127.0.0.1'
      @port = opts[:port] || 6379
      @db = opts[:db] || 0
      @timeout = opts[:timeout] || 0
      connect
    end

    def to_s
      "Redis Client connected to #{@host}:#{@port} against DB #{@db}"
    end

    # Shorthand for getting all the elements in a list.
    def list(key)
      call_command([:lrange, key, 0, -1])
    end

    # We need to define type because otherwise it will escape method_missing.
    def type(key)
      call_command([:type, key])
    end

    def sort(key, opts = {})
      cmd = []
      cmd << "SORT #{key}"
      cmd << "BY #{opts[:by]}" if opts[:by]
      cmd << "GET #{[opts[:get]].flatten * ' GET '}" if opts[:get]
      cmd << "#{opts[:order]}" if opts[:order]
      cmd << "LIMIT #{Array(opts[:limit]).join(' ')}" if opts[:limit]
      call_command(cmd)
    end

  private

    def connect
      connect_to(@host, @port, @timeout == 0 ? nil : @timeout)
      call_command([:select, @db]) if @db != 0
      @sock
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
    rescue Errno::ECONNREFUSED
      raise Errno::ECONNREFUSED, "Unable to connect to Redis on #{host}:#{port}"
    end

    def connected?
      !! @sock
    end

    def disconnect
      @sock.close
      @sock = nil
      true
    end

    def reconnect
      disconnect and connect
    end

    def method_missing(*argv)
      call_command(argv)
    end

    # Wrap raw_call_command to handle reconnection on socket error. We
    # try to reconnect just one time, otherwise let the error araise.
    def call_command(argv)
      connect unless connected?
      raw_call_command(argv.dup)
    rescue Errno::ECONNRESET, Errno::EPIPE
      if reconnect
        raw_call_command(argv.dup)
      else
        raise Errno::ECONNRESET
      end
    end

    def raw_call_command(argv)
      bulk = extract_bulk_argument(argv)
      @sock.write(argv.join(" ") + "\r\n")
      @sock.write(bulk + "\r\n") if bulk
      process_reply(argv[0])
    end

    def bulk_command?(argv)
      BulkCommands[argv[0]] and argv.length > 1
    end

    def extract_bulk_argument(argv)
      if bulk_command?(argv)
        bulk = argv[-1].to_s
        argv[-1] = bulk.respond_to?(:bytesize) ? bulk.bytesize : bulk.size
        bulk
      end
    end

    def process_reply(command)
      ReplyProcessor[command][read_reply]
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

      raise Errno::ECONNRESET, "Connection lost" unless reply_type

      format_reply(reply_type, @sock.gets)
    end

    def format_reply(reply_type, line)
      case reply_type
      when "-" then format_error_reply(line)
      when "+" then format_status_reply(line)
      when ":" then format_integer_reply(line)
      when "$" then format_bulk_reply(line)
      when "*" then format_multi_bulk_reply(line)
      else raise ProtocolError.new(reply_type)
      end
    end

    def format_error_reply(line)
      raise "-" + line.strip
    end

    def format_status_reply(line)
      line.strip
    end

    def format_integer_reply(line)
      line.to_i
    end

    def format_bulk_reply(line)
      bulklen = line.to_i
      return nil if bulklen == -1
      reply = @sock.read(bulklen)
      @sock.read(2) # Discard CRLF.
      reply
    end

    def format_multi_bulk_reply(line)
      reply = []
      line.to_i.times { reply << read_reply }
      reply
    end
  end
end
