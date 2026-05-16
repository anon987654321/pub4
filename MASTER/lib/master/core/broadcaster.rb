# frozen_string_literal: true

module Master
  module Core
    # Optional Rails/Action Cable bridge. Runtime code may call this outside
    # Rails, so every broadcast degrades to a no-op when Action Cable is absent.
    class Broadcaster
      class << self
        def broadcast_event(event)
          broadcast("master:events", type: "event", data: event)
        end

        def broadcast_council(summary)
          broadcast("master:council", type: "council", data: summary)
        end

        def broadcast_status(status)
          broadcast("master:status", type: "status", data: status)
        end

        private

        def broadcast(stream, payload)
          return false unless defined?(ActionCable) && ActionCable.respond_to?(:server)

          ActionCable.server.broadcast(stream, payload)
          true
        rescue StandardError
          false
        end
      end
    end
  end
end
