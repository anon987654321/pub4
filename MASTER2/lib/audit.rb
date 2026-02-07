# frozen_string_literal: true

module MASTER
  # Audit - Structured audit findings with severity × effort priority scoring
  # Scans files for code smells and generates prioritized reports
  module Audit
    extend self

    Finding = Struct.new(
      :type,           # Symbol: smell type (e.g., :long_method, :god_class)
      :severity,       # Symbol: :critical, :major, :minor, :info
      :effort,         # Symbol: :low, :medium, :high
      :file,           # String: file path
      :line,           # Integer: line number (optional)
      :message,        # String: description
      :fix_suggestion, # String: how to fix (optional)
      :priority_score, # Float: calculated priority
      keyword_init: true
    ) do
      def calculate_priority
        severity_weight = case severity
                          when :critical then 10.0
                          when :major then 7.0
                          when :minor then 4.0
                          when :info then 2.0
                          else 5.0
                          end

        effort_weight = case effort
                        when :low then 1.0
                        when :medium then 0.5
                        when :high then 0.2
                        else 0.5
                        end

        self.priority_score = severity_weight * effort_weight
      end
    end

    class Report
      attr_reader :findings, :created_at

      def initialize
        @findings = []
        @created_at = Time.now.utc
      end

      def add(finding)
        finding.calculate_priority
        @findings << finding
      end

      def prioritized
        @findings.sort_by { |f| -f.priority_score }
      end

      def by_severity(severity)
        @findings.select { |f| f.severity == severity }
      end

      def by_file(file)
        @findings.select { |f| f.file == file }
      end

      def critical_count
        by_severity(:critical).size
      end

      def major_count
        by_severity(:major).size
      end

      def total_count
        @findings.size
      end

      def summary
        {
          total: total_count,
          critical: critical_count,
          major: major_count,
          minor: by_severity(:minor).size,
          info: by_severity(:info).size,
          top_priority: prioritized.first(5).map(&:message),
        }
      end

      def to_s
        lines = ["Audit Report (#{@findings.size} findings)", ""]

        prioritized.first(10).each_with_index do |f, i|
          lines << "#{i + 1}. [#{f.severity.to_s.upcase}] #{f.type} (priority: #{f.priority_score.round(1)})"
          lines << "   File: #{f.file}#{f.line ? ":#{f.line}" : ""}"
          lines << "   #{f.message}"
          lines << "   Fix: #{f.fix_suggestion}" if f.fix_suggestion
          lines << ""
        end

        lines << "..." if @findings.size > 10
        lines.join("\n")
      end
    end

    def scan(files, options = {})
      report = Report.new
      smells_data = load_smells_data

      files.each do |file|
        next unless File.exist?(file)

        begin
          code = File.read(file, encoding: "UTF-8")
          scan_file(file, code, report, smells_data, options)
        rescue StandardError => e
          Logging.warn("Audit: Failed to scan #{file}: #{e.message}")
        end
      end

      Result.ok(report: report)
    rescue StandardError => e
      Result.err("Audit scan failed: #{e.message}")
    end

    private

    def scan_file(file, code, report, smells_data, options)
      lines = code.lines

      # Check file length
      if lines.size > 300
        report.add(Finding.new(
          type: :god_class,
          severity: :major,
          effort: :high,
          file: file,
          message: "File has #{lines.size} lines (> 300)",
          fix_suggestion: "Extract classes or modules",
        ))
      elsif lines.size > 200
        report.add(Finding.new(
          type: :large_file,
          severity: :minor,
          effort: :medium,
          file: file,
          message: "File has #{lines.size} lines (> 200)",
          fix_suggestion: "Consider splitting into smaller files",
        ))
      end

      # Use Smells module if available
      if defined?(MASTER::Smells)
        smell_results = Smells.analyze(code, file)
        smell_results.each do |smell|
          severity = case smell[:smell]
                     when :long_method, :god_class then :major
                     when :long_parameter_list, :message_chains then :minor
                     else :info
                     end

          effort = case smell[:smell]
                   when :god_class then :high
                   when :long_method then :medium
                   else :low
                   end

          report.add(Finding.new(
            type: smell[:smell],
            severity: severity,
            effort: effort,
            file: file,
            line: smell[:line],
            message: smell[:message],
            fix_suggestion: smell[:fix],
          ))
        end
      end

      # Check against smells.yml patterns
      check_smell_patterns(file, code, report, smells_data)
    end

    def check_smell_patterns(file, code, report, smells_data)
      return unless smells_data

      # Check for generic verbs
      if smells_data[:generic_verbs]
        smells_data[:generic_verbs].each do |verb, alternatives|
          pattern = /\bdef\s+(\w*#{verb}\w*)\b/i
          code.scan(pattern) do |match|
            method_name = match[0]
            report.add(Finding.new(
              type: :generic_verb,
              severity: :info,
              effort: :low,
              file: file,
              message: "Generic verb in method name: #{method_name}",
              fix_suggestion: "Consider: #{alternatives.sample}",
            ))
          end
        end
      end

      # Check for vague nouns
      if smells_data[:vague_nouns]
        smells_data[:vague_nouns].each do |noun, alternatives|
          pattern = /\b(#{noun})\b/i
          if code.match?(pattern)
            report.add(Finding.new(
              type: :vague_naming,
              severity: :info,
              effort: :low,
              file: file,
              message: "Vague noun: #{noun}",
              fix_suggestion: "Consider: #{alternatives.sample}",
            ))
          end
        end
      end
    end

    def load_smells_data
      smells_file = File.join(MASTER.root, "data", "smells.yml")
      return nil unless File.exist?(smells_file)

      YAML.load_file(smells_file, symbolize_names: true)
    rescue StandardError => e
      Logging.warn("Audit: Failed to load smells.yml: #{e.message}")
      nil
    end
  end
end
