# frozen_string_literal: true

require "yaml"

module MASTER
  module Friction
    # FrictionRecorder — lightweight session-scoped event log.
    # Call FrictionRecorder.record(:pattern_id, context) from any subsystem
    # when a known friction signal fires. SessionRetrospective reads this at
    # session end to synthesise the retrospective.
    #
    # Design: append-only in-memory array (APPEND_ONLY axiom).
    # Persisted to data/friction_log.jsonl if MASTER_FRICTION_LOG is set.
    module FrictionRecorder
      extend self

      LOG_PATH = File.join(File.dirname(__FILE__), "../../data/friction_log.jsonl")

      def reset!
        @events = []
      end

      def events
        @events ||= []
      end

      # Record a friction event.
      # @param pattern_id [Symbol] must match a key in friction_patterns.yml
      # @param context [Hash] file:, line:, detail: etc.
      def record(pattern_id, context = {})
        event = {
          id: pattern_id.to_sym,
          timestamp: Time.now.utc.iso8601,
          context: context,
        }
        events << event
        persist(event) if ENV["MASTER_FRICTION_LOG"]
        Logging.dmesg_log("friction", message: "signal=#{pattern_id} ctx=#{context.inspect}") if defined?(Logging)
        event
      end

      # Summary grouped by pattern_id for retrospective.
      def summary
        events.group_by { |e| e[:id] }
              .transform_values(&:size)
      end

      # Were any critical-severity patterns fired this session?
      def critical?
        patterns = load_patterns
        events.any? do |e|
          patterns.dig(e[:id].to_s, "severity") == "critical"
        end
      end

      private

      def persist(event)
        File.open(LOG_PATH, "a") { |f| f.puts(JSON.generate(event)) }
      rescue StandardError
        # best-effort
      end

      def load_patterns
        path = File.join(File.dirname(__FILE__), "../../data/friction_patterns.yml")
        YAML.safe_load_file(path, permitted_classes: [Symbol])&.fetch("patterns", {}) || {}
      rescue StandardError
        {}
      end
    end
  end
end
