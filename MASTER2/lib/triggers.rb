# frozen_string_literal: true

module MASTER
  # Triggers -- proactive event-driven actions without user prompting
  # Stolen from OpenClaw: auto-reply on patterns, file changes, system events
  module Triggers
    extend self

    @rules = []

    class << self
      def register(event, pattern: nil, &action)
        @rules << { event: event, pattern: pattern, action: action }
        Logging.dmesg_log("triggers", message: "registered #{event}")
      end

      def fire(event, context = {})
        matching = @rules.select { |r| r[:event] == event }
        matching.select! { |r| r[:pattern].nil? || context.to_s.match?(r[:pattern]) }
        return if matching.empty?

        Logging.dmesg_log("triggers", message: "ENTER fire #{event} (#{matching.size} rules)")
        matching.each do |rule|
          rule[:action].call(context)
        rescue StandardError => e
          Logging.dmesg_log("triggers", message: "#{event} handler error: #{e.message}")
        end
      end

      def clear
        @rules = []
      end

      # Built-in triggers -- wire these at boot
      def install_defaults
        # After scan completes, if violations found, offer auto-fix
        register(:after_scan) do |ctx|
          count = ctx[:violations]&.size || 0
          if count > 0
            Logging.dmesg_log("triggers", message: "#{count} violations found, queuing auto-fix")
            Scheduler.add("fix #{ctx[:file]}", interval: :once) if ctx[:file]
          end
        end

        # On error, record for learning
        register(:on_error) do |ctx|
          AgentAutonomy.record_correction(
            original: ctx[:output].to_s[0..200],
            corrected: "",
            context: ctx[:error].to_s[0..200]
          ) if defined?(AgentAutonomy)
        end

        # Budget low -- switch to cheap tier proactively
        register(:budget_low) do |_ctx|
          Logging.dmesg_log("triggers", message: "budget low, switching to fast tier")
        end

        Logging.dmesg_log("triggers", message: "defaults installed")
      end
    end
  end
end
