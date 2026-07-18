# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "severity"

module Master
  module Fix
    class ConflictResolver
      LOG_PATH = "runtime/conflict_log.jsonl"
      DRY_RULES = %w[DRY duplicate_code].freeze
      WET_AHA = "WET/AHA".freeze
      DUPLICATION_THRESHOLD = 3

      def initialize(root:, bus: nil, config: nil, law_resolver: nil)
        @root = root
        @bus = bus
        @config = config || load_config
        @law_resolver = law_resolver || Ground::LawResolver.new
        @rules_index = build_rules_index
      end

      def filter_findings(findings)
        rows = findings.map { |finding| normalize(finding) }
        rows = suppress_dry_below_rule_of_three(rows)
        suppress_lower_priority_laws(rows)
      end

      def reject_higher_priority?(original_violation:, before:, after:, path:)
        original_rank = Severity.rank(original_violation[:severity] || original_violation["severity"])
        introduced = after.map { |finding| normalize(finding).merge("file" => path) } -
                     before.map { |finding| normalize(finding).merge("file" => path) }
        blocker = introduced.find { |finding| Severity.rank(finding["severity"]) > original_rank }
        return false unless blocker

        log_conflict(
          rule_a: original_violation[:rule] || original_violation["rule"],
          rule_b: blocker["rule"],
          resolution: "reject fix: introduced higher-priority #{blocker["severity"]} finding",
          file: path,
          line: blocker["line"]
        )
        true
      end

      private

      attr_reader :root, :bus, :config

      def suppress_dry_below_rule_of_three(rows)
        dry_rows = rows.select { |finding| DRY_RULES.include?(finding["rule"]) }
        return rows unless dry_rows.any? && dry_rows.size < DUPLICATION_THRESHOLD

        dry_rows.each do |finding|
          log_conflict(
            rule_a: finding["rule"],
            rule_b: WET_AHA,
            resolution: "favor WET/AHA below three duplications",
            file: finding["file"],
            line: finding["line"]
          )
        end
        rows - dry_rows
      end

      def suppress_lower_priority_laws(rows)
        rows.group_by { |finding| [finding["file"], finding["line"]] }.values.reduce(rows) do |remaining, group|
          next remaining if group.size < 2

          winner = pick_group_winner(group)
          remaining - (group - [winner])
        end
      end

      def pick_group_winner(group)
        group.reduce(group.first) { |best, finding| resolve_pair(best, finding) }
      end

      def resolve_pair(best, finding)
        favored = @law_resolver.winner(best["rule"], finding["rule"], rules_index: @rules_index)
        if favored == best["rule"]
          log_conflict(rule_a: best["rule"], rule_b: finding["rule"],
            resolution: "law priority favors #{best["rule"]}", file: finding["file"], line: finding["line"])
          best
        else
          log_conflict(rule_a: finding["rule"], rule_b: best["rule"],
            resolution: "law priority favors #{finding["rule"]}", file: best["file"], line: best["line"])
          finding
        end
      end

      def build_rules_index
        Master.flatten_rules(Master.load_rules(root: @root).fetch("rules", {}))
          .each_with_object({}) do |entry, index|
            next unless entry.is_a?(Hash) && entry["id"]

            index[entry["id"].to_s] = entry
          end
      end

      def log_conflict(rule_a:, rule_b:, resolution:, file:, line:)
        payload = {
          timestamp: Time.now.utc.iso8601,
          strategy: config.fetch("strategy", "highest_priority_wins"),
          prompt_user: config.fetch("prompt_user", false),
          rule_a: rule_a.to_s,
          rule_b: rule_b.to_s,
          resolution: resolution.to_s,
          file: file.to_s,
          line: line.to_i
        }
        FileUtils.mkdir_p(File.dirname(log_path))
        File.write(log_path, "#{JSON.generate(payload)}\n", mode: "a")
        bus&.publish("conflict:resolved", payload)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "conflict_resolver.log", event_bus: bus)
      end

      def normalize(finding)
        hash = finding.respond_to?(:to_h) ? finding.to_h : finding
        hash.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
      end

      def log_path
        File.join(root, LOG_PATH)
      end

      def load_config
        soul = Master.load_yaml(Master.data_path("soul.yml"))
        soul.dig("negotiable", "conflict_resolution") || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ConflictResolver.load_config")
        {}
      end
    end
  end
end
