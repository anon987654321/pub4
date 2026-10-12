# frozen_string_literal: true

require "socket"
require "openssl"
require "timeout"
require "set"
require "fileutils"
require_relative "chat"
require_relative "irc/wire"
require_relative "irc/events"
require_relative "irc/commands"

module Master
  module Io
    # IRC client transport. TLS with certificate and hostname verification on
    # port 6697 unless plain text is asked for by name; no reconnect; the only
    # automatic reply is PONG. Incoming text is sanitized by Chat::Policy.
    class Irc < Chat::Transport
      include Events
      include Commands

      DEFAULT_PORT = 6697
      CONNECT_TIMEOUT = 10
      NICK_TRIES = 5
      LIST_SHOWN = 20

      # A channel name: # or &, then up to 49 characters that are not space, comma or BEL.
      ROOM = /\A[#&][^\s,\a]{1,49}\z/

      # A nick: a letter or one of the IRC specials, then up to 29 word or special characters.
      NICK = /\A[A-Za-z\[\]\\`_^{|}][\w\[\]\\`^{|}-]{0,29}\z/

      # LIST filter: users above or below a count, or a short channel-name wildcard.
      LIST_FILTER = /\A(?:[<>]\d{1,6}|[#*?\w.-]{1,50})\z/

      IP_NOTE = "your IP address is visible to the network; use a cloak/VPN if that matters"

      attr_reader :nick, :host, :channels

      class << self
        # Verification flags live here so a test can read them without a socket.
        def tls_context
          OpenSSL::SSL::SSLContext.new.tap do |context|
            context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER, verify_hostname: true)
            context.min_version = OpenSSL::SSL::TLS1_2_VERSION
            context.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
          end
        end

        def parse_target(arg)
          host, port = arg.to_s.strip.split(":", 2)
          raise ArgumentError, "host required" if host.to_s.empty? || host !~ /\A[\w.-]+\z/
          raise ArgumentError, "bad port" if port && port !~ /\A\d{1,5}\z/

          [host, (port || DEFAULT_PORT).to_i]
        end
      end

      # connector: ->(host, port, tls:) returning an IO-like (tests pass a duplex).
      def initialize(connector: nil, env: ENV, **opts)
        super(**opts)

        @connector = connector
        @env = env
        @channels = {}
        @names = {}
        @wlock = Mutex.new
        reset
      end

      def name = "irc"
      def capabilities = %i[join part say action names topic list nick]
      def live? = !@io.nil? && !@io.closed?
      def last_room = @channels.keys.last

      def connect(target, nick:, plain: false)
        raise "already connected to #{@host}" if live?

        host, port = self.class.parse_target(target)
        raise ArgumentError, "bad nick" unless nick.to_s.match?(NICK)

        reset
        policy.speak = false
        @host = host
        @base_nick = @nick = nick
        @plain = plain

        show("irc0: WARNING plain-text connection, nothing is encrypted") if plain
        @io = (@connector || method(:open_socket)).call(host, port, tls: !plain)
        security = plain ? "plain-text, unverified" : "tls, cert ok"
        show("irc0 at net0: connected to #{host} (#{security}), nick #{nick}")
        show("irc0: #{IP_NOTE}")

        register
        @reader = Thread.new { read_loop }
        self
      end

      def disconnect(message = nil)
        return unless live?

        begin
          raw(Wire.line("QUIT", message.to_s.empty? ? "bye" : Chat::Policy.sanitize(message, max: 200)))
        rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e
          Master::Ground::Swallow.log(e, context: "Io::Irc#disconnect")
        end
        close_io
        @reader&.join(1)
        show("irc0: disconnected from #{@host}")
      end

      def status
        chans = @channels.empty? ? "none" : @channels.keys.join(" ")
        state = live? ? "#{@host} (#{@plain ? 'plain-text' : 'tls'})" : "not connected"
        "irc0: #{state}, nick #{@nick || 'none'}, channels #{chans}, #{policy.mode}"
      end

      private

      def reset
        @io = nil
        @registered = false
        @nick_try = 0
        @listed = 0
        @channels.clear
        @names.clear
      end

      def open_socket(host, port, tls:)
        tcp = Socket.tcp(host, port, connect_timeout: CONNECT_TIMEOUT)
        return tcp unless tls

        ssl = OpenSSL::SSL::SSLSocket.new(tcp, self.class.tls_context)
        ssl.hostname = host
        ssl.sync_close = true

        Timeout.timeout(CONNECT_TIMEOUT) { ssl.connect }
        ssl.post_connection_check(host)
        ssl
      rescue StandardError
        tcp&.close
        raise
      end

      def register
        @sasl = !@env["MASTER_IRC_PASSWORD"].to_s.empty?
        raw("CAP REQ :sasl") if @sasl
        raw(Wire.line("NICK", @nick))
        raw(Wire.line("USER", @nick, "0", "*", @nick))
      end

      def raw(line)
        @wlock.synchronize do
          @io.write("#{line}\r\n")
          @io.flush if @io.respond_to?(:flush)
        end
      end

      def deliver(room, text, action: false)
        raise ArgumentError, "bad target" unless room.to_s.match?(ROOM) || room.to_s.match?(NICK)

        raw(Wire.line("PRIVMSG", room, action ? "\x01ACTION #{text}\x01" : text))
      end

      def split_text(room, text, action: false) = Wire.split_message(room, text, action:)

      # One malformed or hostile line must not end the session.
      def dispatch_line(raw_line)
        (msg = Wire.parse(raw_line)) && handle(msg)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Io::Irc#dispatch_line")
      end

      def close_io
        @io&.close
      rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e
        Master::Ground::Swallow.log(e, context: "Io::Irc#close_io")
      end

      def read_loop
        buffer = String.new(encoding: Encoding::BINARY)

        loop do
          buffer << @io.readpartial(4096)
          Wire.drain(buffer).each { |l| dispatch_line(l) }
        end
      rescue EOFError, IOError, SystemCallError, OpenSSL::SSL::SSLError
        close_io
        emit(:info, text: "connection closed", line: "irc0: connection to #{@host} closed")
      end

      def show(line)
        log(line)
        super
      end

      def log(line)
        return unless @env["MASTER_IRC_LOG"] == "1"

        dir = File.join(Master::ROOT, ".master", "irc")
        FileUtils.mkdir_p(dir, mode: 0o700)
        File.open(File.join(dir, "#{@host}-#{Time.now.strftime('%Y%m%d')}.log"), "a", 0o600) do |file|
          file.puts("#{Time.now.strftime('%H:%M:%S')} #{line}")
        end
      end
    end
  end
end
