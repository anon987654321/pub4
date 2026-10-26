# frozen_string_literal: true

require "socket"
require "json"
require "timeout"

module Master
  module Mobile
    # The companion's side of the face protocol FaceServer speaks.
    class FaceClient
      def initialize(socket_path:, timeout_s: 5)
        @path = socket_path
        @timeout_s = timeout_s
      end

      def connect!
        @io = Timeout.timeout(@timeout_s) { UNIXSocket.new(@path) }
        read_until("hello_ok")
        self
      end

      def close
        @io&.close
        @io = nil
      end

      def ping
        send_msg("ping")
        read_until("pong")
      end

      def utterance(text, source: "companion")
        send_msg("utterance", "text" => text.to_s, "source" => source.to_s)
        read_until("say")
      end

      def listen_start = send_msg("listen_start")

      def listen_stop = send_msg("listen_stop")

      def cancel(reason: "companion") = send_msg("cancel", "reason" => reason.to_s)

      private

      def send_msg(type, fields = {})
        raise IOError, "face client is not connected" unless @io

        @io.puts(JSON.generate({ "type" => type }.merge(fields)))
        @io.flush
      end

      def read_until(wanted, limit: 20)
        limit.times do
          line = Timeout.timeout(@timeout_s) { @io.gets }
          raise IOError, "face socket closed" unless line

          message = JSON.parse(line)
          return message if message["type"] == wanted
        end
        raise IOError, "no #{wanted} within #{limit} messages"
      end
    end
  end
end
