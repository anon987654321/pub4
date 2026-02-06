# frozen_string_literal: true

# MultiFileAnalyzer - Parallel analysis of directories
# Ported from cli_v39.rb with enhancements

module MASTER
  class MultiFileAnalyzer
    MAX_FILES = 50
    MAX_TOTAL_LINES = 10_000
    
    def initialize(llm = nil)
      @llm = llm
      @results = []
    end
    
    def analyze(paths)
      files = expand_paths(paths).take(MAX_FILES)
      
      return Result.err("No files found") if files.empty?
      return Result.err("Too many files: #{files.size} > #{MAX_FILES}") if files.size > MAX_FILES
      
      total_lines = files.sum { |f| File.readlines(f).size rescue 0 }
      return Result.err("Too many lines: #{total_lines} > #{MAX_TOTAL_LINES}") if total_lines > MAX_TOTAL_LINES
      
      # Analyze files (parallel-ready but sequential for now)
      @results = files.map { |file| analyze_single(file) }
      
      Result.ok(aggregate_results)
    end
    
    def hotspots
      @results
        .select { |r| (r[:violations]&.size || 0) >= 5 }
        .sort_by { |r| -(r[:violations]&.size || 0) }
    end
    
    private
    
    def expand_paths(paths)
      Array(paths).flat_map do |path|
        if File.directory?(path)
          Dir.glob("#{path}/**/*.rb")
             .reject { |f| f.include?('/vendor/') || f.include?('/node_modules/') }
        elsif File.file?(path)
          [path]
        else
          []
        end
      end.uniq.select { |f| File.file?(f) }
    end
    
    def analyze_single(file)
      code = File.read(file)
      lines = code.lines.size
      violations = scan_violations(code, file)
      smells = detect_smells(code)
      
      {
        file: file,
        lines: lines,
        violations: violations,
        smells: smells,
        score: calculate_score(violations, smells)
      }
    rescue => e
      { file: file, error: e.message, violations: [], smells: [], score: 0 }
    end
    
    def scan_violations(code, file)
      violations = []
      
      code.lines.each_with_index do |line, i|
        ln = i + 1
        violations << { line: ln, type: :trailing_whitespace, severity: :low } if line =~ /[ \t]+$/
        violations << { line: ln, type: :debug_code, severity: :high } if line =~ /\b(binding\.pry|debugger|byebug)\b/
        violations << { line: ln, type: :puts_debug, severity: :medium } if line =~ /^\s*puts\s+["']/
        violations << { line: ln, type: :hardcoded_secret, severity: :critical } if line =~ /(api_key|password|secret)\s*=\s*['"][^'"]+['"]/i
        violations << { line: ln, type: :sql_injection, severity: :critical } if line =~ /execute.*#\{|WHERE.*#\{/
        violations << { line: ln, type: :long_line, severity: :low } if line.length > 120
      end
      
      violations
    end
    
    def detect_smells(code)
      smells = []
      
      # God class (too many methods)
      method_count = code.scan(/^\s*def\s+/).size
      smells << { type: :god_class, confidence: 0.8 } if method_count > 20
      
      # Long method detection
      in_method = false
      method_lines = 0
      code.lines.each do |line|
        if line =~ /^\s*def\s+/
          in_method = true
          method_lines = 0
        elsif line =~ /^\s*end\s*$/
          smells << { type: :long_method, confidence: 0.7 } if in_method && method_lines > 30
          in_method = false
        elsif in_method
          method_lines += 1
        end
      end
      
      # Deep nesting
      max_depth = code.lines.map { |l| l.match(/^(\s*)/)[1].length / 2 }.max || 0
      smells << { type: :deep_nesting, confidence: 0.6 } if max_depth > 5
      
      # Duplicate string literals
      strings = code.scan(/['"][^'"]{10,}['"]/)
      duplicates = strings.group_by(&:itself).select { |_, v| v.size > 2 }
      smells << { type: :magic_strings, confidence: 0.5, count: duplicates.size } if duplicates.any?
      
      smells
    end
    
    def calculate_score(violations, smells)
      base = 100
      base -= violations.size * 2
      base -= smells.size * 5
      [base, 0].max
    end
    
    def aggregate_results
      {
        total_files: @results.size,
        total_lines: @results.sum { |r| r[:lines] || 0 },
        total_violations: @results.sum { |r| r[:violations]&.size || 0 },
        total_smells: @results.sum { |r| r[:smells]&.size || 0 },
        average_score: (@results.sum { |r| r[:score] || 0 } / [@results.size, 1].max.to_f).round(1),
        hotspots: hotspots.map { |r| { file: r[:file], violations: r[:violations]&.size || 0 } },
        by_file: @results
      }
    end
  end
end
