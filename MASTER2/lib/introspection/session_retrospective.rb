# frozen_string_literal: true

require "yaml"
require_relative "friction_recorder"

module MASTER
  module Friction
    # SessionRetrospective -- end-of-session synthesis of friction events.
    # Produces a structured report: what fired, why it matters, what to do.
    # Optionally enriches via LLM for deeper pattern analysis.
    #
    # Called automatically at REPL exit (lib/boot.rb) and on demand:
    #   > introspect
    module SessionRetrospective
      extend self

      def run(use_llm: false)
        events   = FrictionRecorder.events
        patterns = load_patterns
        grouped  = events.group_by { |e| e[:id] }

        return { status: :clean, items: [] } if grouped.empty?

        items = grouped.map do |pattern_id, occurrences|
          pattern = patterns[pattern_id.to_s] || {}
          {
            id: pattern_id,
            count: occurrences.size,
            description: pattern["description"] || pattern_id.to_s,
            severity: pattern["severity"] || "unknown",
            remedy: pattern["remedy"] || "No remedy defined.",
            wishlist: pattern["wishlist_item"],
            examples: occurrences.first(3).map { |e| e[:context] },
          }
        end
        items = items.sort_by { |i| severity_rank(i[:severity]) }

        report = { status: :friction_found, items: items }
        report[:llm_analysis] = llm_enrich(items) if use_llm && defined?(LLM)
        report
      end

      # Format the report as dmesg-style output for the REPL.
      def format(report)
        return "retrospect: clean session -- no friction recorded" if report[:status] == :clean

        lines = ["retrospect: #{report[:items].size} friction pattern(s) this session"]
        report[:items].each do |item|
          lines << "  #{item[:severity].upcase} [#{item[:count]}x] #{item[:description]}"
          lines << "    -> #{item[:remedy]}"
        end
        lines << report[:llm_analysis] if report[:llm_analysis]
        lines.join("\n")
      end

      # Detect config drift: YAML keys in data/ with no Ruby reader.
      # Part of wishlist item 1 (split-brain config).
      def check_config_drift
        data_dir  = File.join(MASTER.root, "data")
        lib_dir   = File.join(MASTER.root, "lib")
        all_rb    = Dir.glob(File.join(lib_dir, "**", "*.rb")).map { |f| File.read(f) }.join("\n")
        orphans   = []

        Dir.glob(File.join(data_dir, "*.yml")).each do |yml_path|
          keys = top_level_keys(yml_path)
          keys.each do |key|
            orphans << { file: File.basename(yml_path), key: key } unless all_rb.include?(key)
          end
        end

        orphans
      end

      # Run config drift check and record friction if orphans found.
      def audit_config_drift
        orphans = check_config_drift
        FrictionRecorder.record(:split_brain_drift, orphans: orphans.first(5)) if orphans.any?
        orphans
      end

      private

      def severity_rank(sev)
        { "critical" => 0, "high" => 1, "medium" => 2, "low" => 3 }[sev] || 4
      end

      def load_patterns
        path = File.join(MASTER.root, "data", "friction_patterns.yml")
        YAML.safe_load_file(path, permitted_classes: [Symbol])&.fetch("patterns", {}) || {}
      rescue StandardError
        {}
      end

      def top_level_keys(yml_path)
        YAML.safe_load_file(yml_path, permitted_classes: [Symbol])&.keys&.map(&:to_s) || []
      rescue StandardError
        []
      end

      def llm_enrich(items)
        summaries = items.map { |i| "#{i[:severity]}: #{i[:description]} (#{i[:count]}x)" }.join("; ")
        prompt = "Synthesise these session friction events into 2-3 actionable improvements. Be brief: #{summaries}"
        result = LLM.ask(prompt, tier: :fast)
        result.ok? ? result.value[:content] : nil
      rescue StandardError
        nil
      end
    end
  end
end
