# encoding: UTF-8

# Redis client based on RubyRedis, original work of Salvatore Sanfilippo
# http://github.com/antirez/redis/blob/4a327b4af9885d89b5860548f44569d1d2bde5ab/client-libraries/ruby_2/rubyredis.rb
#
# Some improvements where inspired by the Redis-rb library, including the testing suite.
# http://github.com/ezmobius/redis-rb/
require 'socket'

module Ohm
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
    class ProtocolError < RuntimeError
      def initialize(reply_type)
        super("Protocol error, got '#{reply_type}' as initial reply byte")
      end
    end

    BULK_COMMANDS = {
      :echo => true,
      :getset => true,
      :lpush => true,
      :lrem => true,
      :lset => true,
      :rpoplpush => true,
      :rpush => true,
      :sadd => true,
      :set => true,
      :setnx => true,
      :sismember => true,
      :smove => true,
      :srem => true,
      :zadd => true,
      :zincrby => true,
      :zrem => true,
      :zscore => true
    }

    MULTI_BULK_COMMANDS = {
      :mset => true,
      :msetnx => true
    }

    PROCESSOR_IDENTITY = lambda { |reply| reply }
    PROCESSOR_CONVERT_TO_BOOL = lambda { |reply| reply == 0 ? false : reply }
    PROCESSOR_SPLIT_KEYS = lambda { |reply| reply.split(" ") }
    PROCESSOR_INFO = lambda { |reply| Hash[*(reply.lines.map { |l| l.chomp.split(":", 2) }.flatten)] }

    REPLY_PROCESSOR = {
      :exists => PROCESSOR_CONVERT_TO_BOOL,
      :sismember=> PROCESSOR_CONVERT_TO_BOOL,
      :sadd=> PROCESSOR_CONVERT_TO_BOOL,
      :srem=> PROCESSOR_CONVERT_TO_BOOL,
      :smove=> PROCESSOR_CONVERT_TO_BOOL,
      :zadd => PROCESSOR_CONVERT_TO_BOOL,
      :zrem => PROCESSOR_CONVERT_TO_BOOL,
      :move=> PROCESSOR_CONVERT_TO_BOOL,
      :setnx=> PROCESSOR_CONVERT_TO_BOOL,
      :del=> PROCESSOR_CONVERT_TO_BOOL,
      :renamenx=> PROCESSOR_CONVERT_TO_BOOL,
      :expire=> PROCESSOR_CONVERT_TO_BOOL,
      :keys => PROCESSOR_SPLIT_KEYS,
      :info => PROCESSOR_INFO
    }

    REPLY_PROCESSOR.send(:initialize) do |hash, key|
      hash[key] = PROCESSOR_IDENTITY
    end

    def initialize(options = {})
      @host = options[:host] || '127.0.0.1'
      @port = options[:port] || 6379
      @db = options[:db] || 0
      @timeout = options[:timeout] || 0
      @password = options[:password]
      connect
    end

    def version
      @version ||= info["redis_version"]
    end

    def support_mset?
      @support_mset.nil? ?
        @support_mset = version >= "1.05" :
        @support_mset
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
      call_command([:auth, @password]) if @password
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
    rescue Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED
      if reconnect
        raw_call_command(argv.dup)
      else
        raise Errno::ECONNRESET
      end
    end

    def raw_call_command(argv)
      bulk_command?(argv) ?
        process_bulk_command(argv) :
        multi_bulk_command?(argv) ?
          process_multi_bulk_command(argv) :
          process_command(argv)
      process_reply(argv[0])
    end

    def process_command(argv)
      @sock.write("#{argv.join(" ")}\r\n")
    end

    def process_bulk_command(argv)
      bulk = argv.pop.to_s
      argv.push ssize(bulk)
      @sock.write("#{argv.join(" ")}\r\n")
      @sock.write("#{bulk}\r\n")
    end

    def process_multi_bulk_command(argv)
      params = argv.pop.to_a.flatten
      params.unshift(argv[0])

      command = ["*#{params.size}"]
      params.each do |param|
        param = param.to_s
        command << "$#{ssize(param)}"
        command << param
      end

      @sock.write(command.map { |cmd| "#{cmd}\r\n"}.join)
    end

    def bulk_command?(argv)
      BULK_COMMANDS[argv[0]] and argv.length > 1
    end

    def multi_bulk_command?(argv)
      MULTI_BULK_COMMANDS[argv[0]]
    end

    def process_reply(command)
      REPLY_PROCESSOR[command][read_reply]
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
      return if bulklen == -1
      reply = @sock.read(bulklen)
      @sock.read(2) # Discard CRLF.

      reply.respond_to?(:force_encoding) ?
        reply.force_encoding("UTF-8") :
        reply
    end

    def format_multi_bulk_reply(line)
      reply = []
      line.to_i.times { reply << read_reply }
      reply
    end

    def ssize(string)
      string.respond_to?(:bytesize) ? string.bytesize : string.size
    end
  end
end
