# frozen_string_literal: true

module MASTER
  # Engine - Unified code quality scan facade
  # Delegates to Smells, Violations, and BugHunting modules
  # Provides scan, deep_scan, and quick_scan entry points
  # Ported from MASTER v1, adapted for MASTER2's architecture
  module Engine
    MAX_METHOD_LINES = 20
    MAX_FILE_LINES = 300

    class << self
      # Basic structural scan - long methods, god classes, deep nesting
      def scan(path)
        return Result.err('Path not found') unless File.exist?(path)

        if File.directory?(path)
          files = Dir[File.join(path, '**', '*.rb')]
          issues = files.flat_map { |f| scan_file(f) }
        else
          issues = scan_file(path)
        end

        Result.ok(issues)
      end

      # Deep scan - adds smell analysis and cyclic dependency detection
      def deep_scan(path)
        return Result.err('Path not found') unless File.exist?(path)

        issues = []

        if File.directory?(path)
          files = Dir[File.join(path, '**', '*.rb')]
          files.each do |f|
            content = File.read(f) rescue next
            issues += scan_file(f)
            
            # Add smell analysis if module is available
            if defined?(Smells)
              smells = Smells.detect(content, path: f) rescue []
              issues += smells.map { |s| s.merge(file: f, type: :smell) }
            end
          end

          # Check for cyclic dependencies if Smells module supports it
          if defined?(Smells) && Smells.respond_to?(:cyclic_deps?)
            cycle = Smells.cyclic_deps?(files) rescue nil
            issues << { file: path, type: :cyclic_dependency, cycle: cycle[:cycle] } if cycle
          end
        else
          content = File.read(path)
          issues = scan_file(path)
          
          if defined?(Smells)
            smells = Smells.detect(content, path: path) rescue []
            issues += smells.map { |s| s.merge(file: path, type: :smell) }
          end
        end

        Result.ok(issues.uniq { |i| [i[:file], i[:type] || i[:smell], i[:line]] })
      end

      # Quick scan - fast summary stats without detailed analysis
      def quick_scan(path)
        return Result.err('Path not found') unless File.exist?(path)

        files = File.directory?(path) ? Dir[File.join(path, '**', '*.rb')] : [path]
        
        stats = {
          files: files.size,
          total_lines: files.sum { |f| File.read(f).lines.size rescue 0 },
          long_files: files.count { |f| (File.read(f).lines.size rescue 0) > MAX_FILE_LINES },
          avg_file_size: 0
        }

        stats[:avg_file_size] = (stats[:total_lines].to_f / files.size).round(1) if files.any?

        # Add module counts if available
        if defined?(MASTER::Axioms)
          stats[:axioms] = MASTER::Axioms.count rescue 0
        end

        if defined?(Smells)
          stats[:smell_patterns] = Smells.all_patterns.size rescue 0
        end

        Result.ok(stats)
      end

      # Scan with specific focus areas
      def focused_scan(path, focus: [:complexity, :duplication, :security])
        return Result.err('Path not found') unless File.exist?(path)

        issues = []
        files = File.directory?(path) ? Dir[File.join(path, '**', '*.rb')] : [path]

        files.each do |file|
          content = File.read(file) rescue next

          if focus.include?(:complexity)
            issues += scan_file(file)
          end

          if focus.include?(:duplication) && defined?(Smells)
            dups = Smells.detect(content, path: file, types: [:duplication]) rescue []
            issues += dups.map { |d| d.merge(file: file, type: :duplication) }
          end

          if focus.include?(:security) && defined?(BugHunting)
            bugs = BugHunting.scan(content, path: file) rescue []
            issues += bugs.map { |b| b.merge(file: file, type: :security) }
          end
        end

        Result.ok(issues)
      end

      # Get scan summary for display
      def scan_summary(scan_result)
        return {} unless scan_result.ok?

        issues = scan_result.value
        {
          total_issues: issues.size,
          by_type: issues.group_by { |i| i[:type] }.transform_values(&:size),
          by_severity: issues.group_by { |i| i[:severity] || :medium }.transform_values(&:size),
          files_affected: issues.map { |i| i[:file] }.uniq.size
        }
      end

      private

      # Scan individual file for basic structural issues
      def scan_file(path)
        content = File.read(path)
        issues = []

        # Long methods
        content.scan(/^\s*def\s+\w+.*?^\s*end/m).each do |method|
          lines = method.lines.size
          if lines > MAX_METHOD_LINES
            issues << { 
              file: path, 
              type: :long_method, 
              lines: lines,
              severity: lines > 50 ? :high : :medium,
              message: "Method has #{lines} lines (max: #{MAX_METHOD_LINES})"
            }
          end
        end

        # God class
        lines = content.lines.size
        if lines > MAX_FILE_LINES
          issues << { 
            file: path, 
            type: :god_class, 
            lines: lines,
            severity: lines > 500 ? :high : :medium,
            message: "File has #{lines} lines (max: #{MAX_FILE_LINES})"
          }
        end

        # Deep nesting (more than 3 levels)
        max_nesting = 0
        current_nesting = 0
        content.each_line do |line|
          # Count block starts
          current_nesting += line.scan(/\b(if|unless|while|until|for|begin|class|module|def|case)\b/).size
          current_nesting += line.scan(/\bdo\b|\{/).size
          # Count block ends
          current_nesting -= line.scan(/\bend\b|\}/).size
          max_nesting = [max_nesting, current_nesting].max
        end

        if max_nesting > 3
          issues << { 
            file: path, 
            type: :deep_nesting, 
            depth: max_nesting,
            severity: max_nesting > 5 ? :high : :medium,
            message: "Maximum nesting depth: #{max_nesting}"
          }
        end

        issues
      rescue => e
        [{ file: path, type: :error, message: e.message, severity: :low }]
      end
    end
  end
end
