# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "severity"
require_relative "priority"

module Master
  module Fix
    class ConflictResolver
      LOG_PATH = "runtime/conflict_log.jsonl"
      # Append-only with no cap previously ran unbounded -- reached 890MB
      # alongside activity.jsonl's 1.2GB, together filling the disk and
      # crashing an in-progress /fix round. Same rotate-not-truncate fix.
      LOG_MAX_BYTES = 25 * 1024 * 1024
      # How many rotated generations (.1, .2, ...) to keep before the oldest
      # is discarded, so a slow-burn conflict-heavy period doesn't just move
      # the unbounded-growth problem from one file to an unbounded set of them.
      LOG_GENERATIONS = 3
      DRY_RULES = %w[DRY duplicate_code].freeze
      WET_AHA = "WET/AHA".freeze
      DUPLICATION_THRESHOLD = 3

      def initialize(root:, bus: nil, config: nil, law_resolver: nil)
        @root = root
        @bus = bus
        @config = config || load_config
        @law_resolver = law_resolver || Ground::LawResolver.new
        @rules_index = Priority.rules_index(root: @root)
      end

      def filter_findings(findings)
        rows = findings.map { |finding| normalize(finding) }
        suppress_dry_below_rule_of_three(rows).then { |kept| suppress_lower_priority_laws(kept) }
      end

      # Would applying this fix trade the original violation for a worse one?
      def reject_higher_priority?(original_violation:, before:, after:, path:)
        baseline = priority_of(original_violation)
        blocker = findings_introduced(before:, after:, path:).find do |finding|
          Priority.higher?(priority_of(finding), baseline)
        end
        return false unless blocker

        log_conflict(
          rule_a: baseline[:rule_id],
          rule_b: blocker["rule"],
          resolution: "reject fix: introduced higher-priority #{blocker["severity"]} finding",
          file: path,
          line: blocker["line"],
        )
        true
      end

      private

      # Priority tuple for either shape this class sees: an original violation
      # (symbol *or* string keys, hence the double lookup) or a normalized
      # finding (string keys only).
      def priority_of(row)
        {
          rule_id: (row[:rule] || row["rule"]).to_s,
          severity: (row[:severity] || row["severity"]).to_s.to_sym,
          law_resolver: @law_resolver,
          rules_index: @rules_index,
        }
      end

      # Findings present after the fix that were not present before it.
      # Both sides are normalized and file-stamped first so the set difference
      # compares like with like.
      def findings_introduced(before:, after:, path:)
        stamped = ->(rows) { rows.map { |finding| normalize(finding).merge("file" => path) } }
        stamped.call(after) - stamped.call(before)
      end

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
            line: finding["line"],
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

      def log_conflict(rule_a:, rule_b:, resolution:, file:, line:)
        payload = {
          timestamp: Time.now.utc.iso8601,
          strategy: config.fetch("strategy", "highest_priority_wins"),
          prompt_user: config.fetch("prompt_user", false),
          rule_a: rule_a.to_s,
          rule_b: rule_b.to_s,
          resolution: resolution.to_s,
          file: file.to_s,
          line: line.to_i,
        }
        FileUtils.mkdir_p(File.dirname(log_path))
        rotate_log_if_oversized!
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

      def rotate_log_if_oversized!
        return unless File.exist?(log_path) && File.size(log_path) > LOG_MAX_BYTES

        oldest = "#{log_path}.#{LOG_GENERATIONS}"
        File.delete(oldest) if File.exist?(oldest)
        (LOG_GENERATIONS - 1).downto(1) do |i|
          src = "#{log_path}.#{i}"
          File.rename(src, "#{log_path}.#{i + 1}") if File.exist?(src)
        end
        File.rename(log_path, "#{log_path}.1")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ConflictResolver.rotate_log_if_oversized")
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
