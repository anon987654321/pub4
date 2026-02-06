# frozen_string_literal: true

# ConvergenceLoop - Auto-iterate until code reaches target quality
# Ported from cli_v39.rb with enhancements

module MASTER
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
