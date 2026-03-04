# frozen_string_literal: true

module Introspection
  class Architect
    REPORT_WIDTH = 110
    DEFAULT_LIMIT = 100
    SEVERITY_ORDER = %w[error warning info].freeze
    HEADER_DASH_MIN = 12

    def initialize(scope: PolicyViolation.all)
      @scope = scope
    end

    def report(project_id:, limit: DEFAULT_LIMIT)
      violations = fetch_violations(project_id: project_id, limit: limit)
      format_report(violations)
    end

    def format_report(violations)
      return empty_report if violations.empty?

      [
        build_header(violations),
        build_body(violations),
        build_footer(violations)
      ].compact.join("\n")
    end

    private

    attr_reader :scope

    def fetch_violations(project_id:, limit:)
      return [] if project_id.nil?

      scope.where(project_id: project_id)
           .includes(:rule, :source_file, :project)
           .order(created_at: :desc)
           .limit(limit)
           .to_a
    rescue ActiveRecord::StatementInvalid => e
      raise e.class, "Unable to load policy violations: #{e.message}", e.backtrace
    end

    def empty_report
      "No violations found."
    end

    def build_header(violations)
      project_name = violations.first.project&.name || "Unknown Project"
      violation_count = violations.size
      "Architecture Report for #{project_name} (#{violation_count} violations)\n"
    end

    def build_body(violations)
      grouped_by_severity = violations.group_by { |violation| violation.rule.severity.to_s }

      SEVERITY_ORDER.filter_map do |severity|
        severity_violations = grouped_by_severity[severity]
        next if severity_violations.nil? || severity_violations.empty?

        format_severity_section(severity, severity_violations)
      end.join("\n\n") + "\n"
    end

    def format_severity_section(severity, severity_violations)
      lines = []
      lines << "#{severity.upcase} (#{severity_violations.size})"
      lines << "-" * [severity.length + 8, HEADER_DASH_MIN].max

      severity_violations.each do |violation|
        lines.concat(format_violation_lines(violation))
      end

      lines.join("\n")
    end

    def format_violation_lines(violation)
      rule = violation.rule
      source_file = violation.source_file

      axiom_list = rule.respond_to?(:axioms) ? Array(rule.axioms) : []
      violation_count = violation.respond_to?(:occurrences) ? violation.occurrences.to_i : 1
      cost_ratio = compute_cost_ratio(violation)

      [
        wrap_line(
          "#{rule.code}: #{rule.title} (count=#{violation_count}, cost_ratio=#{cost_ratio})"
        ),
        wrap_line(file_location_line(violation, source_file)),
        wrap_line("Message: #{violation.message}"),
        axiom_list.empty? ? nil : wrap_line("Axioms: #{axiom_list.join(', ')}"),
        suggestion_line(violation),
        ""
      ].compact
    end

    def file_location_line(violation, source_file)
      path = source_file&.path || violation.file_path || "unknown"
      line = violation.line_number || "?"
      "File: #{path}:#{line}"
    end

    def suggestion_line(violation)
      return nil unless violation.respond_to?(:suggestion)

      suggestion = violation.suggestion
      return nil if suggestion.nil? || suggestion.to_s.strip.empty?

      wrap_line("Suggestion: #{suggestion}")
    end

    def compute_cost_ratio(violation)
      return "n/a" unless violation.respond_to?(:cost) && violation.respond_to?(:budget)

      budget = violation.budget.to_f
      return "n/a" unless budget.positive?

      (violation.cost.to_f / budget).round(3)
    end

    def wrap_line(text, width: REPORT_WIDTH)
      return "" if text.nil?

      string = text.to_s
      return string if string.length <= width

      string.scan(/.{1,#{width}}/).join("\n")
    end

    def build_footer(violations)
      total_violations = violations.size
      grouped_by_rule = violations.group_by(&:rule_id)

      most_frequent_rule = most_frequent_rule_summary(violations, grouped_by_rule)

      footer_parts = []
      footer_parts << "Total: #{total_violations}"
      footer_parts << "Distinct rules: #{grouped_by_rule.size}"
      footer_parts << most_frequent_rule
      footer_parts.join(" | ")
    end

    def most_frequent_rule_summary(violations, grouped_by_rule)
      rule_id, rule_violations = grouped_by_rule.max_by { |_id, list| list.size }
      return "Most frequent: n/a (0)" if rule_id.nil?

      rule = violations.find { |v| v.rule_id == rule_id }&.rule
      title = rule ? "#{rule.code} #{rule.title}" : "n/a"
      "Most frequent: #{title} (#{rule_violations.size})"
    end
  end
end