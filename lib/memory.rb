# frozen_string_literal: true

module MASTER
  module Memory
    @sessions = {}

    class << self
      def store(key, value)
        @sessions[key] = value
      end

      def fetch(key)
        @sessions[key]
      end

      def clear
        @sessions.clear
      end

      def compress(history, max_tokens: 4000)
        return history if history.size <= 10

        # Keep first 2 and last 8 messages
        history.first(2) + history.last(8)
      end
    end
  end
end
