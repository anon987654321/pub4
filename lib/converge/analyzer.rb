#!/usr/bin/env ruby
# frozen_string_literal: true

# Ruby code analyzer for convergence system
# Detects violations of design principles defined in master.yml

require 'json'
require 'pathname'

module Converge
  class Analyzer
    THRESHOLDS = {
      max_method_lines: 20,
      max_file_lines: 200,
      max_complexity: 10,
      duplication_trigger: 3
    }.freeze

    def initialize(paths)
      @paths = Array(paths)
      @violations = []
    end

    def analyze
      @paths.each do |pattern|
        Dir.glob(pattern).each do |file|
          next unless File.file?(file) && file.end_with?('.rb')
          analyze_file(file)
        end
      end
      @violations
    end

    def to_json
      JSON.pretty_generate({
        timestamp: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
        violations: @violations,
        summary: {
          total: @violations.size,
          by_type: @violations.group_by { |v| v[:type] }.transform_values(&:size)
        }
      })
    end

    private

    def analyze_file(file)
      content = File.read(file)
      lines = content.lines
      
      # Check file size
      if lines.size > THRESHOLDS[:max_file_lines]
        @violations << {
          type: 'file_size_lines',
          file: file,
          line: 1,
          message: "File has #{lines.size} lines (max: #{THRESHOLDS[:max_file_lines]})",
          severity: 'warning',
          actual: lines.size,
          threshold: THRESHOLDS[:max_file_lines]
        }
      end

      # Analyze methods
      analyze_methods(file, content)
      
      # Check for single-letter variables (except i, j, k in loops)
      analyze_variable_names(file, content)
      
      # Simple duplication detection
      analyze_duplication(file, lines)
    end

    def analyze_methods(file, content)
      methods = extract_methods(content)
      
      methods.each do |method|
        line_count = method[:lines].size
        
        if line_count > THRESHOLDS[:max_method_lines]
          @violations << {
            type: 'small_functions',
            file: file,
            line: method[:start_line],
            message: "Method '#{method[:name]}' has #{line_count} lines (max: #{THRESHOLDS[:max_method_lines]})",
            severity: 'warning',
            method_name: method[:name],
            actual: line_count,
            threshold: THRESHOLDS[:max_method_lines]
          }
        end

        # Check complexity (count nested conditionals and loops)
        complexity = calculate_complexity(method[:lines])
        if complexity > THRESHOLDS[:max_complexity]
          @violations << {
            type: 'max_complexity',
            file: file,
            line: method[:start_line],
            message: "Method '#{method[:name]}' has complexity #{complexity} (max: #{THRESHOLDS[:max_complexity]})",
            severity: 'warning',
            method_name: method[:name],
            actual: complexity,
            threshold: THRESHOLDS[:max_complexity]
          }
        end
      end
    end

    def extract_methods(content)
      methods = []
      lines = content.lines
      current_method = nil
      indent_level = 0

      lines.each_with_index do |line, idx|
        # Match method definitions: def method_name or def self.method_name
        if line =~ /^\s*def\s+(self\.)?(\w+)/
          method_name = $2
          current_method = {
            name: method_name,
            start_line: idx + 1,
            lines: [line],
            indent: line[/^\s*/].length
          }
        elsif current_method
          current_method[:lines] << line
          
          # Check if method ends
          if line =~ /^\s*end\s*$/ && line[/^\s*/].length == current_method[:indent]
            methods << current_method
            current_method = nil
          end
        end
      end

      methods
    end

    def calculate_complexity(lines)
      complexity = 1 # Base complexity
      
      lines.each do |line|
        # Count decision points (conditionals and loops)
        complexity += 1 if line =~ /\b(if|unless|elsif|case|when|while|until|for|rescue)\b/
        # Count logical operators (each adds a branch)
        complexity += line.scan(/&&|\|\|/).size
      end
      
      complexity
    end

    def analyze_variable_names(file, content)
      lines = content.lines
      
      lines.each_with_index do |line, idx|
        # Skip loop variables i, j, k
        next if line =~ /\.(each|map|select|reject).*do\s*\|[ijk]\|/
        next if line =~ /for\s+[ijk]\s+in/
        
        # Find single-letter variable assignments (excluding class names and constants)
        if line =~ /\b([a-z])\s*=/
          var = $1
          next if %w[i j k].include?(var)
          
          @violations << {
            type: 'meaningful_names',
            file: file,
            line: idx + 1,
            message: "Single-letter variable '#{var}' found (except i,j,k in loops)",
            severity: 'info',
            variable: var
          }
        end
      end
    end

    def analyze_duplication(file, lines)
      # Simple duplication: find lines that appear 3+ times
      line_counts = Hash.new(0)
      
      lines.each_with_index do |line, idx|
        # Skip empty lines, comments, and very short lines
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?('#') || stripped.length < 20
        
        line_counts[stripped] ||= []
        line_counts[stripped] << idx + 1
      end
      
      line_counts.each do |content, occurrences|
        if occurrences.size >= THRESHOLDS[:duplication_trigger]
          @violations << {
            type: 'duplication_trigger',
            file: file,
            line: occurrences.first,
            message: "Line duplicated #{occurrences.size} times (threshold: #{THRESHOLDS[:duplication_trigger]})",
            severity: 'info',
            occurrences: occurrences,
            content: content[0..50] + (content.length > 50 ? '...' : '')
          }
        end
      end
    end
  end
end

# CLI interface
if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: #{$0} <path_pattern> [<path_pattern> ...]"
    puts "Example: #{$0} 'rails/**/*.rb' 'openbsd/**/*.rb'"
    exit 1
  end

  analyzer = Converge::Analyzer.new(ARGV)
  analyzer.analyze
  puts analyzer.to_json
end
