#!/usr/bin/env ruby
# frozen_string_literal: true

# Reporter for convergence violations
# Merges and formats violation reports

require 'json'

module Converge
  class Reporter
    def initialize
      @violations = []
    end

    def add_violations(violations)
      @violations.concat(Array(violations))
    end

    def merge_report(json_string)
      data = JSON.parse(json_string, symbolize_names: true)
      add_violations(data[:violations])
    end

    def summary
      {
        total: @violations.size,
        by_type: @violations.group_by { |v| v[:type] }.transform_values(&:size),
        by_severity: @violations.group_by { |v| v[:severity] }.transform_values(&:size),
        by_file: @violations.group_by { |v| v[:file] }.transform_values(&:size)
      }
    end

    def to_json
      JSON.pretty_generate({
        timestamp: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        violations: @violations,
        summary: summary
      })
    end

    def format_console
      output = []
      output << "\n=== Convergence Violations Report ==="
      output << "Total: #{@violations.size} violations"
      output << ""

      summary[:by_type].each do |type, count|
        output << "  #{type}: #{count}"
      end

      output << ""
      output << "=== Details ==="
      
      @violations.group_by { |v| v[:file] }.each do |file, file_violations|
        output << ""
        output << "File: #{file} (#{file_violations.size} violations)"
        
        file_violations.sort_by { |v| v[:line] }.each do |v|
          output << "  Line #{v[:line]} [#{v[:severity]}]: #{v[:message]}"
        end
      end

      output.join("\n")
    end

    def has_violations?
      !@violations.empty?
    end

    def critical_violations
      @violations.select { |v| v[:severity] == 'error' }
    end
  end
end

# CLI interface
if __FILE__ == $0
  reporter = Converge::Reporter.new
  
  ARGV.each do |file|
    if File.exist?(file)
      reporter.merge_report(File.read(file))
    else
      STDERR.puts "File not found: #{file}"
    end
  end

  puts reporter.format_console
end
