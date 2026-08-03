# frozen_string_literal: true

require "socket"

module Brgen
  module Irc
    # The socket harness around Session. One thread reads client commands, a second
    # polls the web side and relays; a mutex serialises writes so the two never
    # interleave a line. Each thread checks out its own ActiveRecord connection —
    # this runs outside the request cycle.
    class Server
      def initialize(host: ENV.fetch("IRC_HOST", "127.0.0.1"),
                     port: Integer(ENV.fetch("IRC_PORT", "6667")),
                     bridge: Bridge.new, logger: Rails.logger)
        @host = host
        @port = port
        @bridge = bridge
        @logger = logger
      end

      def start
        server = TCPServer.new(@host, @port)
        @logger&.info("irc-gateway listening on #{@host}:#{@port}")
        loop do
          client = server.accept
          Thread.new(client) { |socket| serve(socket) }
        end
      end

      private

      def serve(socket)
        session = Session.new(bridge: @bridge)
        write_lock = Mutex.new
        emit = ->(lines) { with_writes(socket, write_lock, lines) }

        poller = Thread.new do
          loop do
            sleep 2
            ActiveRecord::Base.connection_pool.with_connection { emit.call(session.poll) }
          end
        rescue StandardError
          nil
        end

        socket.each_line do |line|
          ActiveRecord::Base.connection_pool.with_connection { emit.call(session.handle(line)) }
        end
      rescue StandardError => e
        @logger&.warn("irc client dropped: #{e.class}: #{e.message}")
      ensure
        poller&.kill
        socket.close rescue nil
      end

      def with_writes(socket, lock, lines)
        return if lines.nil? || lines.empty?

        lock.synchronize do
          lines.each { |line| socket.write("#{line}\r\n") }
        end
      rescue IOError, Errno::EPIPE
        nil
      end
    end
  end
end
