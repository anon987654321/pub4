# frozen_string_literal: true

module MASTER
  # Canonical code analysis algorithms extracted from duplicate implementations
  # Used by Engine, Layers, Scopes, Smells, and Violations modules
  module Analyzers
    # Nesting depth analysis - tracks def/class/module/if/unless/case/while/until/for/begin/do blocks
    # Returns maximum nesting level as integer
    module NestingAnalyzer
      def self.depth(code)
        nesting = 0
        max_seen = 0

        code.each_line do |line|
          stripped = line.strip
          if stripped =~ /^\s*(def|class|module|if|unless|case|while|until|for|begin|do)\b/
            nesting += 1
            max_seen = [max_seen, nesting].max
          elsif stripped == 'end'
            nesting = [0, nesting - 1].max
          end
        end

        max_seen
      end
    end

    # Method length analysis - returns array of {name:, start_line:, length:} hashes
    # Uses nesting-aware stack to handle nested methods correctly
    module MethodLengthAnalyzer
      def self.scan(code)
        results = []
        method_starts = []
        nesting = 0
        lines = code.lines

        lines.each_with_index do |line, idx|
          stripped = line.strip

          if stripped =~ /^\s*def\s+(\w+)/
            method_name = ::Regexp.last_match(1)
            method_starts << { line: idx + 1, nesting: nesting, name: method_name }
            nesting += 1
          elsif stripped == 'end'
            if method_starts.any? && nesting.positive?
              start = method_starts.pop
              length = idx - start[:line] + 1
              results << {
                name: start[:name],
                start_line: start[:line],
                length: length
              }
            end
            nesting = [0, nesting - 1].max
          elsif stripped =~ /^\s*(class|module|if|unless|case|while|until|for|begin|do)\b/
            nesting += 1
          end
        end

        results
      end
    end

    # Repeated string detection - returns array of {string:, count:} hashes
    # Scans both single and double quoted strings
    module RepeatedStringDetector
      def self.find(code, min_length: 8, min_count: 3)
        strings = code.scan(/"[^"]{#{min_length},}"|'[^']{#{min_length},}'/).flatten
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
          Dir[File.join(path, '**', '*.rb')]
        else
          [path]
        end
      end
    end
  end
end
