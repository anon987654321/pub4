#!/usr/bin/env ruby
# frozen_string_literal: true

module MASTER
  # Hook system for extensibility
  # Allows code to register callbacks for lifecycle events
  class Hooks
    EVENTS = %i[
      before_edit
      after_edit
      before_fix
      after_fix
      on_stuck
      on_test_pass
      on_test_fail
      before_evolve
      after_evolve
      on_rollback
      on_converge
      before_llm
      after_llm
    ].freeze

    @registry = Hash.new { |h, k| h[k] = [] }

    class << self
      # Register a hook
      # Usage: Hooks.register(:before_edit, priority: 10) { |data| ... }
      def register(event, priority: 50, &block)
        raise ArgumentError, "Unknown event: #{event}" unless EVENTS.include?(event)
        raise ArgumentError, "Block required" unless block_given?
        
        @registry[event] << { priority: priority, handler: block }
        @registry[event].sort_by! { |h| h[:priority] }
      end

      # Trigger hooks for an event
      # Passes data to each handler
      # Returns modified data
      def trigger(event, data = {})
        return data unless @registry.key?(event)
        
        @registry[event].each do |hook|
          begin
            result = hook[:handler].call(data)
            data = result if result.is_a?(Hash)
          rescue StandardError => e
            warn "Hook error on #{event}: #{e.message}"
          end
        end
        
        data
      end

      # Clear all hooks (mainly for testing)
      def clear!
        @registry.clear
      end

      # List registered hooks
      def list(event = nil)
        if event
          @registry[event]
        else
          @registry
        end
      end

      # Load hooks from database
      def load_from_db
        require_relative 'db'
        
        rows = DB.connection.execute("SELECT * FROM hooks WHERE active = 1 ORDER BY priority ASC")
        
        rows.each do |row|
          event = row['event'].to_sym
          handler_str = row['handler']
          priority = row['priority']
          
          # Create handler from string
          # Supports Ruby class/method or shell command
          if handler_str.include?('::')
            # Ruby class method: "MyClass::my_method"
            klass, method = handler_str.split('::')
            register(event, priority: priority) do |data|
              Object.const_get(klass).send(method, data)
            end
          else
            # Shell command
            register(event, priority: priority) do |data|
              system(handler_str)
              data
            end
          end
        end
      rescue StandardError => e
        warn "Failed to load hooks from DB: #{e.message}"
      end
    end
  end
end
