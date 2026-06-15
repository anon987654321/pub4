# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Trace
  # MemoryTierCompactor — deduplicate and age-rotate the three memory tiers:
  #   working (in-session ring buffer), episodic (NDJSON per session), semantic (SQLite).
  # Run after session save to keep memory lean.
    class MemoryTierCompactor
      EPISODIC_DIR = File.join(Master::ROOT, ".master", "episodic").freeze
      MAX_WORKING = 40 # messages kept in ring buffer
      MAX_EPISODIC = 200 # lines per session episodic file
      MAX_SEMANTIC = 5000 # rows kept in semantic SQLite table

      def initialize(session:, sqlite_memory: nil, event_bus: nil)
        @session = session
        @db = sqlite_memory
        @bus = event_bus
      end

      def compact!
        results = {}
        results[:working] = compact_working
        results[:episodic] = compact_episodic
        results[:semantic] = compact_semantic
        @bus&.publish("memory:compacted", **results)
        Result.ok(results)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "MemoryTierCompactor.compact!", event_bus: @bus)
        Result.err(e.message, category: :infrastructure)
      end

      private

      def compact_working
        msgs = @session.messages
        return 0 if msgs.size <= MAX_WORKING
        @session.messages.replace(msgs.last(MAX_WORKING))
        dropped
      end

      def compact_episodic
        return 0 unless Dir.exist?(EPISODIC_DIR)
        Dir.glob(File.join(EPISODIC_DIR, "*.ndjson")).each do |path|
          lines = File.readlines(path, chomp: true).reject(&:empty?)
          next if lines.size <= MAX_EPISODIC
          dropped = lines.size - MAX_EPISODIC
          File.write(path, lines.last(MAX_EPISODIC).join("\n") + "\n")
          total_dropped += dropped
        end
        total_dropped
      end

      def compact_semantic
        return 0 unless @db
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "MemoryTierCompactor.compact_semantic")
        0
      end
    end
  end
end
