# frozen_string_literal: true

module MASTER
  module Actors
    # Actor Registry - manages all actors in the system
    class Registry
      def initialize(event_bus)
        @event_bus = event_bus
        @actors = {}
        @mutex = Mutex.new
      end

      # Register an actor
      def register(name, actor_class)
        @mutex.synchronize do
          return false if @actors.key?(name)
          
          actor = actor_class.new(name, @event_bus)
          @actors[name] = actor
          @event_bus.publish(:actor_registered, actor: name, class: actor_class.name)
          true
        end
      end

      # Get an actor by name
      def get(name)
        @mutex.synchronize { @actors[name] }
      end

      # Start an actor
      def start(name)
        actor = get(name)
        actor&.start
      end

      # Stop an actor
      def stop(name)
        actor = get(name)
        actor&.stop
      end

      # Start all actors
      def start_all
        @mutex.synchronize do
          @actors.each_value(&:start)
        end
      end

      # Stop all actors
      def stop_all
        @mutex.synchronize do
          @actors.each_value(&:stop)
        end
      end

      # List all actors
      def list
        @mutex.synchronize { @actors.keys }
      end

      # Get actor count
      def count
        @mutex.synchronize { @actors.size }
      end

      # Clear registry (for testing)
      def clear
        stop_all
        @mutex.synchronize { @actors.clear }
      end
    end
  end
end
