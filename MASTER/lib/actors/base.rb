# frozen_string_literal: true

module MASTER
  module Actors
    # Base Actor class for the actor system (Microkernel #2)
    # Actors communicate via events and handle specific responsibilities
    class Base
      attr_reader :name, :state

      def initialize(name, event_bus)
        @name = name
        @event_bus = event_bus
        @state = :initialized
        @mutex = Mutex.new
      end

      # Start the actor
      def start
        @mutex.synchronize do
          return false if @state == :running
          @state = :running
          on_start
          emit(:actor_started, actor: @name)
        end
        true
      end

      # Stop the actor
      def stop
        @mutex.synchronize do
          return false if @state == :stopped
          @state = :stopped
          on_stop
          emit(:actor_stopped, actor: @name)
        end
        true
      end

      # Check if actor is running
      def running?
        @state == :running
      end

      # Handle an event (override in subclasses)
      def handle_event(event)
        # Subclasses implement this
      end

      protected

      # Emit an event
      def emit(event_type, data = {})
        @event_bus.publish(event_type, data.merge(actor: @name))
      end

      # Subscribe to events
      def subscribe(event_type, &handler)
        @event_bus.subscribe(event_type, &handler)
      end

      # Lifecycle hooks (override in subclasses)
      def on_start
      end

      def on_stop
      end
    end
  end
end
