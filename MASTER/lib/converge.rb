# frozen_string_literal: true

# Convergence Implementation - Consolidated convergence checking and looping
# This file consolidates functionality from converge.rb and convergence_loop.rb
# to provide both basic hash-based convergence detection and score-based iteration
# orchestration in a single location.
#
# NOTE: Part of a three-layer architecture:
#   - Converge module: Basic hash-based convergence metrics
#   - ConvergenceLoop class: Score-based iteration orchestration with plateau detection
#   - Evolve: Full self-improvement workflow with chamber integration

module MASTER
  # Converge - Low-level convergence detection using hash comparison
  module Converge
    # Convergence detection thresholds
    MAX_ITERATIONS = 10
    DIFF_THRESHOLD = 0.02  # 2% change = converged

    class << self
      def run(path = '.')
        iteration = 0
        prev_hash = nil

        loop do
          iteration += 1
          return Result.err("Max iterations (#{MAX_ITERATIONS}) reached") if iteration > MAX_ITERATIONS

          # Scan and collect issues
          issues = Engine.scan(File.expand_path(path)).value || []

          # Calculate content hash
          current_hash = content_hash(path)

          # Check convergence
          if prev_hash && change_ratio(prev_hash, current_hash) < DIFF_THRESHOLD
            return Result.ok({
              iterations: iteration,
              status: 'converged',
              final_issues: issues.size
            })
          end

          # No issues = converged
          if issues.empty?
            return Result.ok({
              iterations: iteration,
              status: 'clean',
              final_issues: 0
            })
          end

          prev_hash = current_hash
          yield(iteration, issues) if block_given?
        end
      end

      def audit(current_path, compare_ref = 'HEAD~10')
        current_features = extract_features(current_path)
        historical_features = extract_historical_features(compare_ref)

        missing = historical_features - current_features
        added = current_features - historical_features

        {
          current_count: current_features.size,
          historical_count: historical_features.size,
          missing: missing,
          added: added,
          coverage: current_features.size.to_f / [historical_features.size, 1].max
        }
      end

      private

      def content_hash(path)
        files = Dir.glob(File.join(path, '**', '*.rb'))
        content = files.map { |f| File.read(f) rescue '' }.join
        Digest::SHA256.hexdigest(content)
      end

      def change_ratio(old_hash, new_hash)
        # Same hash = no change (0%), different = full change (100%)
        old_hash == new_hash ? 0.0 : 1.0
      end

      def extract_features(path)
        features = Set.new

        Dir.glob(File.join(path, '**', '*.rb')).each do |file|
          content = File.read(file) rescue next
          # Extract method names
          content.scan(/def\s+(\w+)/).each { |m| features << "method:#{m[0]}" }
          # Extract class names
          content.scan(/class\s+(\w+)/).each { |c| features << "class:#{c[0]}" }
          # Extract module names
          content.scan(/module\s+(\w+)/).each { |m| features << "module:#{m[0]}" }
        end

        features.to_a
      end

      def extract_historical_features(ref)
        features = Set.new

        # Get file list from git ref
        files = `git ls-tree -r --name-only #{ref} 2>/dev/null`.lines.map(&:chomp)
        rb_files = files.select { |f| f.end_with?('.rb') }

        rb_files.each do |file|
          content = `git show #{ref}:#{file} 2>/dev/null`
          next if content.empty?

          content.scan(/def\s+(\w+)/).each { |m| features << "method:#{m[0]}" }
          content.scan(/class\s+(\w+)/).each { |c| features << "class:#{c[0]}" }
          content.scan(/module\s+(\w+)/).each { |m| features << "module:#{m[0]}" }
        end

        features.to_a
      rescue StandardError
        []
      end
    end
  end

  # ConvergenceLoop - Auto-iterate until code reaches target quality
  # Score-based iteration orchestration with plateau detection
  class ConvergenceLoop
    MAX_ITERATIONS = 10
    PLATEAU_THRESHOLD = 0.05  # Stop when improvement < 5%
    TARGET_SCORE = 100
    
    def initialize(llm, analyzer = nil)
      @llm = llm
      @analyzer = analyzer
      @iteration = 0
      @previous_score = 0
      @history = []
    end
    
    def run(target, &on_iteration)
      files = collect_files(target)
      return Result.err("No files to analyze") if files.empty?
      
      loop do
        @iteration += 1
        puts "\n[converge] iteration=#{@iteration}"
        
        # Analyze all files
        results = analyze_files(files)
        violations = results.flat_map { |r| r[:violations] || [] }
        score = calculate_score(violations, files.size)
        
        @history << { iteration: @iteration, score: score, violations: violations.size }
        
        puts "[converge] score=#{score}/100 violations=#{violations.size}"
        yield(@iteration, score, violations) if block_given?
        
        # Check exit conditions
        break if perfect_score?(score)
        break if plateau?(score)
        break if @iteration >= MAX_ITERATIONS
        
        # Attempt fixes
        fixed = attempt_fixes(violations)
        puts "[converge] fixed=#{fixed}"
        
        @previous_score = score
      end
      
      Result.ok({
        iterations: @iteration,
        final_score: @history.last&.dig(:score) || 0,
        history: @history
      })
    end
    
    private
    
    def collect_files(target)
      if File.file?(target)
        [target]
      elsif File.directory?(target)
        Dir.glob(File.join(target, '**', '*.rb'))
           .reject { |f| f.include?('/vendor/') || f.include?('/test/') }
           .take(50)
      else
        []
      end
    end
    
    def analyze_files(files)
      files.map do |file|
        code = File.read(file)
        violations = scan_violations(code, file)
        { file: file, violations: violations }
      end
    end
    
    def scan_violations(code, file)
      violations = []
      
      # Basic pattern detection
      code.lines.each_with_index do |line, i|
        violations << { file: file, line: i + 1, type: :trailing_whitespace } if line =~ /[ \t]+$/
        violations << { file: file, line: i + 1, type: :debug_code } if line =~ /\b(puts|p|pp|binding\.pry|debugger)\b/
        violations << { file: file, line: i + 1, type: :todo } if line =~ /\bTODO\b/i
        violations << { file: file, line: i + 1, type: :long_line } if line.length > 120
      end
      
      violations
    end
    
    def calculate_score(violations, file_count)
      return 100 if violations.empty?
      penalty = violations.size.to_f / [file_count, 1].max
      [100 - (penalty * 10), 0].max.round
    end
    
    def perfect_score?(score)
      score >= TARGET_SCORE
    end
    
    def plateau?(score)
      return false if @iteration <= 1
      improvement = (score - @previous_score).abs
      improvement < (PLATEAU_THRESHOLD * 100)
    end
    
    def attempt_fixes(violations)
      fixed = 0
      
      # Group by file
      by_file = violations.group_by { |v| v[:file] }
      
      by_file.each do |file, file_violations|
        code = File.read(file)
        original = code.dup
        
        # Auto-fix safe violations
        file_violations.each do |v|
          case v[:type]
          when :trailing_whitespace
            code = code.gsub(/[ \t]+$/, '')
            fixed += 1
          end
        end
        
        # Only write if changed and still valid Ruby
        if code != original && valid_ruby?(code)
          File.write(file, code)
        end
      end
      
      fixed
    end
    
    def valid_ruby?(code)
      RubyVM::InstructionSequence.compile(code)
      true
    rescue SyntaxError
      false
    end
  end
end
