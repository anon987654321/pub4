# frozen_string_literal: true

require_relative 'event'

module MASTER
  module Events
    # Event Bus - Pub/Sub system for decoupling (Event-Driven #4)
    # Enables event sourcing and replay capabilities
    class Bus
      def initialize
        @subscribers = Hash.new { |h, k| h[k] = [] }
        @event_log = []
        @mutex = Mutex.new
      end

      # Publish an event to all subscribers
      def publish(event_type, data = {})
        event = Event.new(type: event_type, data: data)
        
        @mutex.synchronize do
          @event_log << event
          
          # Notify subscribers
          subscribers = @subscribers[event.type] + @subscribers[:all]
          subscribers.each do |handler|
            begin
              handler.call(event)
            rescue => e
              warn "Event handler error for #{event.type}: #{e.message}"
            end
          end
        end
        
        event
      end

      # Subscribe to specific event type or :all for all events
      def subscribe(event_type = :all, &handler)
        raise ArgumentError, "Block required" unless block_given?
        
        @mutex.synchronize do
          @subscribers[event_type] << handler
        end
        
        # Return unsubscribe function
        -> { unsubscribe(event_type, handler) }
      end

      # Unsubscribe a handler
      def unsubscribe(event_type, handler)
        @mutex.synchronize do
          @subscribers[event_type].delete(handler)
        end
      end

      # Replay events from a specific time
      def replay(from: nil, to: nil)
        events = @mutex.synchronize { @event_log.dup }
        
        events = events.select { |e| e.timestamp >= from } if from
        events = events.select { |e| e.timestamp <= to } if to
        
        events
      end

      # Get all events
      def events
        @mutex.synchronize { @event_log.dup }
      end

      # Get event count
      def event_count
        @mutex.synchronize { @event_log.size }
      end

      # Clear event log (for testing)
      def clear
        @mutex.synchronize do
          @event_log.clear
          @subscribers.clear
        end
      end

      # Get subscriber count for event type
      def subscriber_count(event_type = :all)
        @mutex.synchronize { @subscribers[event_type].size }
      end

      # Find events by type
      def find_by_type(event_type)
        @mutex.synchronize do
          @event_log.select { |e| e.type == event_type }
        end
      end
    end
  end
end
