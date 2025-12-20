#!/usr/bin/env ruby
# frozen_string_literal: true

# Shell script analyzer for convergence system
# Detects violations in zsh scripts

require 'json'
require 'pathname'

module Converge
  class ShellAnalyzer
    THRESHOLDS = {
      max_function_lines: 20,
      max_file_lines: 200
    }.freeze

    BANNED_TOOLS = %w[
      python bash sed awk tr wc head tail cut find sudo
    ].freeze

    def initialize(paths)
      @paths = Array(paths)
      @violations = []
    end

    def analyze
      @paths.each do |pattern|
        Dir.glob(pattern).each do |file|
          next unless File.file?(file) && file.end_with?('.sh')
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
      
      # Check if it's a bash script (should be zsh)
      if lines.first =~ /^#!.*bash/
        @violations << {
          type: 'banned_shell',
          file: file,
          line: 1,
          message: 'Script uses bash instead of zsh',
          severity: 'error',
          actual: 'bash',
          expected: 'zsh'
        }
      end

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

      # Analyze functions
      analyze_functions(file, content)
      
      # Check for banned tool usage
      analyze_banned_tools(file, lines)
      
      # Check for proper zsh parameter expansion usage
      analyze_parameter_expansion(file, lines)
    end

    def analyze_functions(file, content)
      functions = extract_functions(content)
      
      functions.each do |func|
        line_count = func[:lines].size
        
        if line_count > THRESHOLDS[:max_function_lines]
          @violations << {
            type: 'small_functions',
            file: file,
            line: func[:start_line],
            message: "Function '#{func[:name]}' has #{line_count} lines (max: #{THRESHOLDS[:max_function_lines]})",
            severity: 'warning',
            function_name: func[:name],
            actual: line_count,
            threshold: THRESHOLDS[:max_function_lines]
          }
        end
      end
    end

    def extract_functions(content)
      functions = []
      lines = content.lines
      current_func = nil
      brace_count = 0

      lines.each_with_index do |line, idx|
        # Match function definitions: function_name() { or function function_name {
        if line =~ /^\s*(\w+)\s*\(\s*\)\s*\{/ || line =~ /^\s*function\s+(\w+)\s*\{/
          func_name = $1
          current_func = {
            name: func_name,
            start_line: idx + 1,
            lines: [line]
          }
          brace_count = 1
        elsif current_func
          current_func[:lines] << line
          
          # Count braces to find function end
          brace_count += line.scan(/\{/).size
          brace_count -= line.scan(/\}/).size
          
          if brace_count == 0
            functions << current_func
            current_func = nil
          end
        end
      end

      functions
    end

    def analyze_banned_tools(file, lines)
      lines.each_with_index do |line, idx|
        # Skip comments
        next if line =~ /^\s*#/
        
        BANNED_TOOLS.each do |tool|
          # Check for tool usage (as command, not in strings)
          if line =~ /\b#{tool}\b/ && line !~ /["'].*\b#{tool}\b.*["']/
            @violations << {
              type: 'banned_tool',
              file: file,
              line: idx + 1,
              message: "Banned tool '#{tool}' used (use zsh parameter expansion or allowed tools)",
              severity: 'error',
              tool: tool,
              line_content: line.strip
            }
          end
        end
      end
    end

    def analyze_parameter_expansion(file, lines)
      lines.each_with_index do |line, idx|
        # Skip comments and empty lines
        next if line =~ /^\s*#/ || line.strip.empty?
        
        # Detect potential sed usage patterns that should use parameter expansion
        if line =~ /\bsed\b.*s\// && line !~ /^\s*#/
          @violations << {
            type: 'parameter_expansion',
            file: file,
            line: idx + 1,
            message: 'Consider using zsh parameter expansion ${var//pattern/replacement} instead of sed',
            severity: 'info',
            suggestion: 'Use ${var//pattern/replacement}'
          }
        end

        # Detect awk for field extraction
        if line =~ /\bawk\b.*\{.*print/ && line !~ /^\s*#/
          @violations << {
            type: 'parameter_expansion',
            file: file,
            line: idx + 1,
            message: 'Consider using zsh parameter expansion ${${(s: :)line}[2]} instead of awk',
            severity: 'info',
            suggestion: 'Use ${${(s: :)line}[N]} for field extraction'
          }
        end

        # Detect wc for counting
        if line =~ /\|\s*wc\s+-[lw]/ && line !~ /^\s*#/
          @violations << {
            type: 'parameter_expansion',
            file: file,
            line: idx + 1,
            message: 'Consider using zsh parameter expansion ${#var} instead of wc',
            severity: 'info',
            suggestion: 'Use ${#var} for counting'
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
    puts "Example: #{$0} 'openbsd/**/*.sh' 'rails/**/*.sh'"
    exit 1
  end

  analyzer = Converge::ShellAnalyzer.new(ARGV)
  analyzer.analyze
  puts analyzer.to_json
end
