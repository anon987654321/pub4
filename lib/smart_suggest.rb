require 'fileutils'
require 'json'

module MASTER
  # SmartSuggest - Proactively analyzes code and suggests improvements
  # Watches files for changes and generates prioritized refactoring suggestions
  class SmartSuggest
    attr_reader :suggestions, :patterns

    def initialize(options = {})
      @confidence_threshold = options[:confidence_threshold] || 0.7
      @max_suggestions = options[:max_suggestions] || 10
      @patterns = load_patterns
      @suggestions = []
    end

    # Watch directory for changes and suggest improvements
    def self.watch(path, options = {}, &block)
      suggester = new(options)
      suggester.watch(path, &block)
    end

    def watch(path, &block)
      files = Dir.glob(File.join(path, '**', '*.rb'))
      files.each do |file|
        suggestions = analyze_file(file)
        suggestions.each do |suggestion|
          yield suggestion if block_given?
        end
      end
    end

    # Analyze a single file and generate suggestions
    def analyze_file(file)
      return [] unless File.exist?(file)
      
      code = File.read(file)
      suggestions = []

      # Detect code smells
      suggestions += detect_god_class(file, code)
      suggestions += detect_long_methods(file, code)
      suggestions += detect_duplicate_code(file, code)
      suggestions += detect_missing_tests(file, code)
      suggestions += detect_magic_numbers(file, code)
      suggestions += detect_complex_conditionals(file, code)

      # Sort by priority (impact × effort)
      suggestions.sort_by! { |s| -s.priority }
      suggestions.take(@max_suggestions)
    end

    # Batch analyze multiple files
    def batch_analyze(paths)
      all_suggestions = []
      paths.each do |path|
        if File.directory?(path)
          Dir.glob(File.join(path, '**', '*.rb')).each do |file|
            all_suggestions += analyze_file(file)
          end
        else
          all_suggestions += analyze_file(path)
        end
      end
      all_suggestions.sort_by! { |s| -s.priority }
      all_suggestions
    end

    private

    def load_patterns
      # Load learned patterns from database
      # For now, return empty hash - will integrate with DB later
      {}
    end

    def detect_god_class(file, code)
      lines = code.lines.count
      methods = code.scan(/^\s*def\s+/).count
      
      if lines > 500 || methods > 30
        impact = lines > 1000 ? :high : :medium
        effort = :high
        confidence = calculate_confidence(lines, 500, 1.5)
        
        [Suggestion.new(
          type: :god_class,
          file: file,
          description: "God class detected: #{lines} lines, #{methods} methods",
          impact: impact,
          effort: effort,
          confidence: confidence,
          line: 1
        )]
      else
        []
      end
    end

    def detect_long_methods(file, code)
      suggestions = []
      current_method = nil
      method_start = 0
      method_lines = 0

      code.lines.each_with_index do |line, idx|
        if line =~ /^\s*def\s+(\w+)/
          # Save previous method if it was long
          if current_method && method_lines > 25
            suggestions << Suggestion.new(
              type: :long_method,
              file: file,
              description: "Long method '#{current_method}': #{method_lines} lines",
              impact: :medium,
              effort: :medium,
              confidence: calculate_confidence(method_lines, 25, 1.2),
              line: method_start
            )
          end
          
          current_method = $1
          method_start = idx + 1
          method_lines = 0
        elsif line =~ /^\s*end\s*$/
          method_lines += 1
          current_method = nil if current_method
        elsif current_method
          method_lines += 1
        end
      end

      # Final check in case the last method in the file is long and was not followed by another `def`
      if current_method && method_lines > 25
        suggestions << Suggestion.new(
          type: :long_method,
          file: file,
          description: "Long method '#{current_method}': #{method_lines} lines",
          impact: :medium,
          effort: :medium,
          confidence: calculate_confidence(method_lines, 25, 1.2),
          line: method_start
        )
      end

      suggestions
    end

    def detect_duplicate_code(file, code)
      # Optimized duplicate detection using hash-based lookup
      suggestions = []
      lines = code.lines
      block_size = 5
      
      return suggestions if lines.size < block_size

      # Map block content to occurrence count and first index for near O(n) detection
      block_counts = Hash.new { |h, k| h[k] = { count: 0, first_index: nil } }

      (0..lines.size - block_size).each do |i|
        block = lines[i, block_size].join
        next if block.strip.empty?

        entry = block_counts[block]
        entry[:count] += 1
        entry[:first_index] = i if entry[:first_index].nil? || i < entry[:first_index]
      end

      duplicate_entry = block_counts.values
        .select { |entry| entry[:count] > 1 }
        .min_by { |entry| entry[:first_index] }

      if duplicate_entry
        suggestions << Suggestion.new(
          type: :duplicate_code,
          file: file,
          description: "Duplicate code block found (#{duplicate_entry[:count]} instances)",
          impact: :medium,
          effort: :medium,
          confidence: 0.8,
          line: duplicate_entry[:first_index] + 1
        )
      end
      
      suggestions
    end

    def detect_missing_tests(file, code)
      suggestions = []
      
      # Check if this is a lib file without corresponding test
      if file.include?('lib/') && !file.include?('test')
        test_file = file.sub('lib/', 'test/test_').sub('.rb', '.rb')
        
        unless File.exist?(test_file)
          suggestions << Suggestion.new(
            type: :missing_tests,
            file: file,
            description: "No test file found: #{test_file}",
            impact: :high,
            effort: :high,
            confidence: 0.9,
            line: 1
          )
        end
      end
      
      suggestions
    end

    def detect_magic_numbers(file, code)
      suggestions = []
      magic_numbers = code.scan(/\b(\d{2,})\b/).flatten.map(&:to_i).uniq
      
      # Filter out common numbers
      magic_numbers.reject! { |n| n == 0 || n == 1 || n == 100 }
      
      if magic_numbers.any?
        suggestions << Suggestion.new(
          type: :magic_numbers,
          file: file,
          description: "Magic numbers found: #{magic_numbers.take(5).join(', ')}",
          impact: :low,
          effort: :low,
          confidence: 0.7,
          line: 1
        )
      end
      
      suggestions
    end

    def detect_complex_conditionals(file, code)
      suggestions = []
      
      code.lines.each_with_index do |line, idx|
        # Count boolean operators in conditionals
        if line =~ /^\s*(if|elsif|unless|while|until)\s+/
          operators = line.scan(/(\&\&|\|\||and|or)/).count
          
          if operators > 2
            suggestions << Suggestion.new(
              type: :complex_conditional,
              file: file,
              description: "Complex conditional with #{operators + 1} conditions",
              impact: :medium,
              effort: :low,
              confidence: 0.85,
              line: idx + 1
            )
          end
        end
      end
      
      suggestions
    end

    def calculate_confidence(value, threshold, factor = 1.5)
      # Calculate confidence based on how far value exceeds threshold
      ratio = value.to_f / threshold
      confidence = [(ratio - 1.0) / factor, 0.9].min
      [confidence, 0.5].max
    end
  end

  # Represents a single refactoring suggestion
  class Suggestion
    attr_reader :type, :file, :description, :impact, :effort, :confidence, :line

    IMPACT_SCORES = { low: 1, medium: 3, high: 5 }
    EFFORT_SCORES = { low: 1, medium: 3, high: 5 }

    def initialize(type:, file:, description:, impact:, effort:, confidence:, line: 1)
      @type = type
      @file = file
      @description = description
      @impact = impact
      @effort = effort
      @confidence = confidence
      @line = line
    end

    # Priority = impact / effort (higher is better)
    def priority
      impact_score = IMPACT_SCORES[@impact] || 3
      effort_score = EFFORT_SCORES[@effort] || 3
      (impact_score.to_f / effort_score * @confidence * 100).round(2)
    end

    def to_s
      "💡 #{@type}: #{@description}\n   File: #{@file}:#{@line}\n   Impact: #{@impact} | Effort: #{@effort} | Confidence: #{(@confidence * 100).round}% | Priority: #{priority}"
    end

    def to_h
      {
        type: @type,
        file: @file,
        description: @description,
        impact: @impact,
        effort: @effort,
        confidence: @confidence,
        line: @line,
        priority: priority
      }
    end
  end
end
