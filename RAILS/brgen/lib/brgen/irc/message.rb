# frozen_string_literal: true

module Brgen
  module Irc
    # One IRC protocol line, parsed or built. Wire format is
    #   [":" prefix SPACE] command [SPACE params] [SPACE ":" trailing] CRLF
    # where the trailing param is the only one allowed to contain spaces.
    Message = Struct.new(:prefix, :command, :params) do
      def self.parse(raw)
        line = raw.to_s.chomp
        prefix = nil
        if line.start_with?(":")
          prefix, line = line[1..].split(" ", 2)
          return nil if line.nil?
        end

        if (idx = line.index(" :"))
          head = line[0...idx]
          trailing = line[(idx + 2)..]
          params = head.split(" ")
          params << trailing
        else
          params = line.split(" ")
        end

        command = params.shift
        return nil if command.nil? || command.empty?

        new(prefix, command.upcase, params)
      end

      # Build a server->client line. The last param is prefixed with ":" when it
      # contains a space, is empty, or itself starts with ":".
      def self.build(command, params = [], prefix: nil)
        # PRIVMSG/NOTICE text is always a trailing param, even one word, so clients
        # render it as message body rather than a bare token.
        force_trailing = %w[PRIVMSG NOTICE].include?(command.to_s.upcase)
        parts = []
        parts << ":#{prefix}" if prefix
        parts << command
        params.each_with_index do |param, i|
          value = param.to_s
          last = i == params.size - 1
          parts << (last && (force_trailing || needs_colon?(value)) ? ":#{value}" : value)
        end
        parts.join(" ")
      end

      def self.needs_colon?(value)
        value.empty? || value.include?(" ") || value.start_with?(":")
      end

      def channel = params.first
      def text = params.last
    end
  end
end
