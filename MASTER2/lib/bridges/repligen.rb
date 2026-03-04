# frozen_string_literal: true

module Bridges
  module Repligen
    DEFAULT_PORT = 50_25
    DEFAULT_TIMEOUT_SECONDS = 5
    DEFAULT_BUFFER_SIZE_BYTES = 1024

    class Client
      attr_reader :host, :port, :timeout

      def initialize(host:, port: DEFAULT_PORT, timeout: DEFAULT_TIMEOUT_SECONDS)
        @host = host
        @port = port
        @timeout = timeout
      end

      def connect
        return socket if defined?(@socket) && @socket && !@socket.closed?

        @socket = TCPSocket.new(host, port)
      end

      def disconnect
        return unless defined?(@socket) && @socket

        @socket.close unless @socket.closed?
        @socket = nil
      end

      def write(data)
        connect
        socket.write(data)
        true
      end

      def read(max_bytes: DEFAULT_BUFFER_SIZE_BYTES)
        connect
        socket.readpartial(max_bytes)
      rescue EOFError
        nil
      end

      private

      def socket
        @socket || raise("Not connected")
      end
    end
  end
end