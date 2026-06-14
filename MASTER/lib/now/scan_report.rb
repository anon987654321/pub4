# frozen_string_literal: true

require_relative "../loop/conflict_resolver"

module Master
  module Now
    class ScanReport
      def initialize(pairs:, profile:, rule_filter:, severity_filter: nil, dry_run: false)
        @pairs = pairs
        @profile = profile
        @rule_filter = rule_filter
        @severity_filter = severity_filter
        @dry_run = dry_run
        @conflicts = Master::Loop::ConflictResolver.new(root: Master::ROOT)
      end

      def render
        return "#{prefix}#{header}clean -- no violations#{suffix}" if total.zero?

        lines = ["#{prefix}#{header}#{total} total violations#{suffix}"]
        lines << evidence_line
        ranked.first(CommandRegistry::SCAN_RULE_GROUP_LIMIT).each do |rule, violations|
          lines << "[#{rule}]"
          lines.concat(violations.first(3).map { |violation| violation_line(violation) })
        end
        lines << omitted_line if omitted_count.positive?
        lines.join("\n")
      end

      private

      attr_reader :pairs, :profile, :rule_filter, :severity_filter, :dry_run, :conflicts

      def by_rule
        @by_rule ||= filtered_violations.each_with_object(Hash.new { |h, k| h[k] = [] }) do |violation, groups|
            next if rule_filter && !rule_filter.include?(violation[:rule].to_s)
            next if severity_filter && !severity_filter.include?(violation[:severity].to_s)

            groups[violation[:rule].to_s] << violation
        end
      end

      def filtered_violations
        conflicts.filter_findings(raw_violations).map { |finding| symbolize_keys(finding) }
      end

      def raw_violations
        pairs.flat_map do |(file, file_result)|
          Result.wrap(file_result).value_or([]).map { |violation| violation.merge(file: file) }
        end
      end

      def symbolize_keys(finding)
        finding.each_with_object({}) { |(key, value), out| out[key.to_sym] = value }
      end

      def total
        @total ||= by_rule.values.sum(&:size)
      end

      def ranked
        @ranked ||= by_rule.sort_by { |rule, violations| [-violations.size, rule] }
      end

      def evidence_line
        "evidence: #{ranked.map { |rule, violations| "#{rule}=#{violations.size}" }.join(", ")}"
      end

      def violation_line(violation)
        "  L#{violation[:line]}: #{violation[:message][0, CommandRegistry::VIOLATION_TRUNCATE]}"
      end

      def omitted_count
        ranked.drop(CommandRegistry::SCAN_RULE_GROUP_LIMIT).sum { |_, violations| violations.size }
      end

      def omitted_line
        "#{omitted_count} more violation(s) omitted"
      end

      def header
        profile ? "[profile: #{profile}] " : ""
      end

      def prefix
        dry_run ? "dry-run: " : ""
      end

      def suffix
        dry_run ? " (no changes made)" : ""
      end
    end
  end
end
