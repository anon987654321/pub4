# frozen_string_literal: true

require "socket"
require "json"
require "fileutils"
require "securerandom"
require_relative "env"

module Master
  module Mobile
    # The face protocol over a Unix socket, one JSON object per line. A
    # companion app sends hello, ping, utterance, listen_start, listen_stop and
    # cancel; the server answers hello_ok, pong, state, face, say and error.
    # Modes share the desktop face's vocabulary (tokens.yml face_interface).
    class FaceServer
      MODES = %w[idle listening thinking working speaking warning error sleeping ready].freeze

      attr_reader :mode

      def initialize(root:, on_utterance: nil, run_id: SecureRandom.uuid, config: Mobile.config,
                     socket_path: nil)
        @root = File.expand_path(root)
        @face = config.fetch("face", {})
        @socket_path = socket_path
        @on_utterance = on_utterance
        @run_id = run_id
        @mode = "idle"
        @listening = false
        @wake_held = false
      end

      def socket_path = @socket_path || File.expand_path(@face["socket"] || ".master/mobile/face.sock", @root)

      def start!
        path = socket_path
        FileUtils.mkdir_p(File.dirname(path))
        clear_stale_socket!(path)
        @server = UNIXServer.new(path)
        File.chmod(0o600, path)
        hold_wake_lock!
        @server
      end

      def stop!
        release_wake_lock!
        @server&.close
        File.delete(socket_path) if File.socket?(socket_path)
      end

      def serve_once
        client = @server.accept
        handle_client(client)
      ensure
        client&.close
      end

      def handle_client(io)
        send_msg(io, "hello_ok", "protocol_version" => @face["protocol_version"] || 1, "run_id" => @run_id,
                                 "profile" => "mobile", "modes" => MODES)
        show(io, "idle")
        while (line = io.gets)
          message = parse(line)
          answer(io, message) if message
        end
      end

      def set_mode!(mode)
        @mode = MODES.include?(mode.to_s) ? mode.to_s : "idle"
      end

      private

      def answer(io, message)
        case message["type"]
        when "ping" then send_msg(io, "pong")
        when "hello" then nil
        when "utterance" then utter(io, message)
        when "listen_start" then listening(io, true)
        when "listen_stop", "cancel" then listening(io, false)
        else send_msg(io, "error", "code" => "unknown_type", "message" => message["type"].to_s)
        end
      end

      def utter(io, message)
        text = message["text"].to_s
        return if text.empty?

        show(io, "thinking")
        reply = @on_utterance&.call(text, message["source"].to_s)
        send_msg(io, "say", "text" => reply.to_s) if reply
        show(io, "idle")
      end

      def listening(io, on)
        @listening = on
        show(io, on ? "listening" : "idle")
      end

      def show(io, mode)
        set_mode!(mode)
        send_msg(io, "state", "mode" => @mode, "listening" => @listening, "summary" => @mode)
        send_msg(io, "face", "expression" => @mode, "attention" => @listening ? "high" : "low")
      end

      def send_msg(io, type, fields = {})
        io.puts(JSON.generate({ "type" => type }.merge(fields)))
        io.flush
      end

      def parse(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      # A socket file with no listener is left by a crash; one with a listener is another host.
      def clear_stale_socket!(path)
        return unless File.exist?(path)

        UNIXSocket.new(path).close
        raise "face socket already in use: #{path}"
      rescue Errno::ECONNREFUSED, Errno::ENOENT
        File.delete(path) if File.exist?(path)
      end

      def hold_wake_lock!
        command = @face["wake_lock"]
        return unless command && Env.on_path?(command)

        @wake_held = system(command)
      end

      def release_wake_lock!
        return unless @wake_held

        command = @face["wake_unlock"]
        system(command) if command && Env.on_path?(command)
        @wake_held = false
      end
    end
  end
end
