# frozen_string_literal: true

module MASTER
  module Memory
    HISTORY_THRESHOLD = 10
    HISTORY_HEAD = 2
    HISTORY_TAIL = 8

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
        return history if history.size <= HISTORY_THRESHOLD

        # Keep first messages for context, last for recency
        history.first(HISTORY_HEAD) + history.last(HISTORY_TAIL)
      end

      def all
        @sessions.dup
      end

      def size
        @sessions.size
      end
    end
  end
end
