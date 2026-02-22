# frozen_string_literal: true

require_relative "prism_analyzer"

module MASTER
  # Canonical code analysis algorithms extracted from duplicate implementations
  # Used by Engine, Layers, Scopes, Smells, and Violations modules
  module Analyzers
    # Nesting depth analysis — delegates to PrismAnalyzer for AST-accurate results;
    # falls back to line-counting heuristic when source has parse errors.
    module NestingAnalyzer
      def self.depth(code)
        prism_depth = PrismAnalyzer.nesting_depth(code)
        return prism_depth if prism_depth.positive? || PrismAnalyzer.parse_errors(code).empty?

        # Fallback: line-counting heuristic
        nesting = 0
        max_seen = 0
        code.each_line do |line|
          stripped = line.strip
          if stripped =~ /^\s*(def|class|module|if|unless|case|while|until|for|begin|do)\b/
            nesting += 1
            max_seen = [max_seen, nesting].max
          elsif stripped == "end"
            nesting = [0, nesting - 1].max
          end
        end
        max_seen
      end
    end

    # Method length analysis — delegates to PrismAnalyzer for AST-accurate results;
    # falls back to nesting-aware line-counting when source has parse errors.
    # Returns array of {name:, start_line:, length:} hashes (param_count added by Prism path).
    module MethodLengthAnalyzer
      def self.scan(code)
        errors = PrismAnalyzer.parse_errors(code)
        return PrismAnalyzer.scan_methods(code) if errors.empty?

        # Fallback: nesting-aware line-counting
        results = []
        method_starts = []
        nesting = 0
        code.lines.each_with_index do |line, idx|
          stripped = line.strip
          case stripped
          when /^\s*def\s+(\w+)/
            method_starts << { line: idx + 1, nesting: nesting, name: ::Regexp.last_match(1) }
            nesting += 1
          when "end"
            if method_starts.any? && nesting.positive?
              start = method_starts.pop
              results << { name: start[:name], start_line: start[:line], length: idx - start[:line] }
            end
            nesting = [0, nesting - 1].max
          when /^\s*(class|module|if|unless|case|while|until|for|begin|do)\b/
            nesting += 1
          end
        end
        results
      end
    end

    # Repeated string detection - returns array of {string:, count:} hashes
    # Scans both single and double quoted strings (including quotes in result)
    module RepeatedStringDetector
      def self.find(code, min_length: 8, min_count: 3)
        # Scan double and single quoted strings with the min_length requirement
        # Pattern matches strings including their quotes
        pattern = /"[^"]{#{min_length},}"|'[^']{#{min_length},}'/
        strings = code.scan(pattern)
        counts = strings.tally

        counts.select { |_, count| count >= min_count }
          .map { |string, count| { string: string, count: count } }
      end
    end

    # File collection utility - handles both directory and single-file inputs
    # Returns array of .rb file paths
    module FileCollector
      def self.ruby_files(path)
        if File.directory?(path)
          Dir[File.join(path, "**", "*.rb")]
        else
          [path]
        end
      end
    end
  end
end
