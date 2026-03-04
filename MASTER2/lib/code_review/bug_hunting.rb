# frozen_string_literal: true

module CodeReview
  class BugHunting
    DEFAULT_MAX_FINDINGS = 25
    SEVERITY_ORDER = { high: 0, medium: 1, low: 2, info: 3 }.freeze

    Finding = Struct.new(:file, :line, :severity, :message, :rule, keyword_init: true)

    def analyze(source_by_path, max_findings: DEFAULT_MAX_FINDINGS)
      return { findings: [], skipped: true, reason: "no files provided" } if source_by_path.nil? || source_by_path.empty?

      findings = source_by_path.flat_map do |path, source|
        scan_file(path.to_s, source.to_s)
      end

      findings = sort_findings(findings).first(max_findings)
      { findings:, skipped: false, reason: nil }
    end

    def format(analysis_result)
      return "No results." if analysis_result.nil?
      return "Skipped: #{analysis_result[:reason] || 'unknown reason'}" if analysis_result[:skipped]

      findings = Array(analysis_result[:findings])
      return "No issues found." if findings.empty?

      lines = findings.map { |f| format_finding(f) }
      ([header_line(findings.size)] + lines).join("\n")
    end

    private

    def scan_file(path, source)
      return [] if source.empty?

      source.each_line.with_index(1).flat_map do |line_text, line_number|
        scan_line(path, line_number, line_text)
      end
    end

    def scan_line(path, line_number, line_text)
      stripped = line_text.strip
      return [] if stripped.empty?

      rules_for_line(stripped).map do |rule|
        Finding.new(
          file: path,
          line: line_number,
          severity: rule[:severity],
          message: rule[:message],
          rule: rule[:rule]
        )
      end
    end

    def rules_for_line(stripped)
      candidates = []
      candidates << rule(:high, "Potentially dangerous eval usage", :eval_usage) if stripped.match?(/\beval\s*\(/)
      candidates << rule(:medium, "Debugger statement left in code", :debugger) if stripped.match?(/\b(binding\.pry|debugger|byebug)\b/)
      candidates << rule(:low, "TODO left in code", :todo) if stripped.match?(/\bTODO\b/)
      candidates
    end

    def rule(severity, message, rule_name)
      { severity:, message:, rule: rule_name }
    end

    def sort_findings(findings)
      findings.sort_by { |f| [SEVERITY_ORDER.fetch(f.severity, 99), f.file, f.line] }
    end

    def header_line(count)
      "Findings (#{count}):"
    end

    def format_finding(finding)
      "#{finding.severity.to_s.upcase}: #{finding.file}:#{finding.line} [#{finding.rule}] #{finding.message}"
    end
  end
end