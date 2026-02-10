# frozen_string_literal: true

require_relative "quality_standards"

module MASTER
  # audit.rb — Code smell detection and quality analysis.
  # Thresholds: reads from QualityStandards (data/quality_thresholds.yml).
  # See also: smells.rb (smell definitions), code_review.rb (pattern detection).
  module Audit
    extend self

    # Finding structure for audit results
    Finding = Struct.new(
      :file,
      :line,
      :severity,
      :effort,
      :category,
      :message,
      :suggestion,
      keyword_init: true
    )

    # Report class for collecting and analyzing findings
    class Report
      attr_reader :findings

      def initialize
        @findings = []
      end

      def add(finding)
        @findings << finding
      end

      # Return findings sorted by priority (severity × effort score)
      def prioritized
        @findings.sort_by do |f|
          severity_score = { critical: 4, high: 3, medium: 2, low: 1 }[f.severity] || 1
          effort_score = { easy: 1, moderate: 2, hard: 3 }[f.effort] || 2
          
          # Higher severity and lower effort = higher priority
          -(severity_score * 10 / effort_score)
        end
      end

      def summary
        by_severity = @findings.group_by(&:severity)
        by_category = @findings.group_by(&:category)
        
        {
          total: @findings.size,
          by_severity: by_severity.transform_values(&:count),
          by_category: by_category.transform_values(&:count)
        }
      end
    end

    # Scan files for code smells
    def scan(files)
      report = Report.new
      files = [files] unless files.is_a?(Array)
      
      files.each do |file|
        next unless File.exist?(file) && file.end_with?(".rb")
        
        begin
          content = File.read(file)
          lines = content.lines
          
          # Check file length
          check_file_length(file, lines, report)
          
          # Check method and variable names
          check_naming(file, content, report)
          
        rescue StandardError => e
          report.add(Finding.new(
            file: file,
            line: 0,
            severity: :low,
            effort: :easy,
            category: :error,
            message: "Could not scan file: #{e.message}",
            suggestion: nil
          ))
        end
      end
      
      Result.ok(report: report)
    end

    private

    def check_file_length(file, lines, report)
      # Use QualityStandards (ONE_SOURCE axiom)
      warn_threshold = QualityStandards.warn_file_lines
      error_threshold = QualityStandards.error_file_lines
      
      length = lines.size
      
      if length > error_threshold
        report.add(Finding.new(
          file: file,
          line: 0,
          severity: :high,
          effort: :hard,
          category: :file_length,
          message: "File is too long (#{length} lines, threshold: #{error_threshold})",
          suggestion: "Split into smaller, focused modules"
        ))
      elsif length > warn_threshold
        report.add(Finding.new(
          file: file,
          line: 0,
          severity: :medium,
          effort: :moderate,
          category: :file_length,
          message: "File is getting long (#{length} lines, threshold: #{warn_threshold})",
          suggestion: "Consider refactoring into smaller files"
        ))
      end
    end

    def check_naming(file, content, report)
      # Generic verb patterns
      generic_verbs = %w[handle process manage do execute perform run]
      
      # Check method names for generic verbs
      content.scan(/^\s*def\s+([a-z_]+[a-z0-9_]*)/i).each do |match|
        method_name = match[0]
        
        generic_verbs.each do |verb|
          if method_name.start_with?(verb) && method_name.length < 15
            report.add(Finding.new(
              file: file,
              line: 0,
              severity: :low,
              effort: :easy,
              category: :naming,
              message: "Method '#{method_name}' uses generic verb '#{verb}'",
              suggestion: "Use more specific verb that describes what is being #{verb}d"
            ))
          end
        end
      end
      
      # Vague noun patterns
      vague_nouns = %w[data info item thing stuff object element]
      
      # Check variable names for vague nouns
      content.scan(/^\s*([a-z_]+[a-z0-9_]*)\s*=/).each do |match|
        var_name = match[0]
        
        vague_nouns.each do |noun|
          if var_name.include?(noun) && var_name.length < 10
            report.add(Finding.new(
              file: file,
              line: 0,
              severity: :low,
              effort: :easy,
              category: :naming,
              message: "Variable '#{var_name}' uses vague noun '#{noun}'",
              suggestion: "Use more descriptive name that indicates purpose"
            ))
          end
        end
      end
    end
  end
end
