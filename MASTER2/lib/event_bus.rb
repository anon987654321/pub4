# frozen_string_literal: true

module MASTER
  # EventBus - Simple publish/subscribe event system
  # Provides decoupled communication between subsystems
  module EventBus
    @subscribers = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new

    class << self
      # Subscribe to an event
      # @param event [Symbol, String] Event name to subscribe to
      # @param subscriber [Object, nil] Optional subscriber identifier (for unsubscribing)
      # @yield [Hash] Called with event data when event is published
      def subscribe(event, subscriber: nil, &handler)
        raise ArgumentError, "Block required for subscribe" unless handler

        event = event.to_sym
        @mutex.synchronize do
          @subscribers[event] << { handler: handler, subscriber: subscriber }
        end
      end

      # Publish an event to all subscribers
      # @param event [Symbol, String] Event name to publish
      # @param data [Hash] Event data passed to handlers
      def publish(event, **data)
        event = event.to_sym
        handlers = @mutex.synchronize { @subscribers[event].dup }

        handlers.each do |entry|
          entry[:handler].call(data)
        rescue StandardError => err
          # Silently rescue handler errors; only log at high trace levels
          if defined?(Logging) && Logging.respond_to?(:trace_level) && Logging.trace_level >= 3
            Logging.dmesg_log("eventbus0", message: "handler error for #{event}: #{err.message}", level: Logging::ALL_EVENTS)
          end
        end
      end

      # Unsubscribe a subscriber from all events
      # @param subscriber [Object] Subscriber identifier to remove
      def unsubscribe(subscriber)
        @mutex.synchronize do
          @subscribers.each_value do |handlers|
            handlers.reject! { |entry| entry[:subscriber] == subscriber }
          end
        end
      end

      # Clear all subscribers (useful for testing)
      def clear!
        @mutex.synchronize { @subscribers.clear }
      end

      # Return list of registered event names
      # @return [Array<Symbol>] List of event names with subscribers
      def registered
        @mutex.synchronize { @subscribers.keys.select { |k| @subscribers[k].any? } }
      end
    end
  end
end
