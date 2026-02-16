# frozen_string_literal: true

require 'yaml'
require_relative 'analyzers'

module MASTER
  # CodeQuality - Unified code quality scan facade
  # Delegates to Smells, Violations, and BugHunting modules
  # Provides scan, deep_scan, and quick_scan entry points
  # Ported from MASTER v1, adapted for MASTER2's architecture
  module CodeQuality
    MAX_METHOD_LINES = 20
    MAX_FILE_LINES = 600

    # Scan profiles for tiered axiom checking
    SCAN_PROFILES = {
      quick: { min_priority: 9, description: "Critical axioms only (~5 axioms)" },
      standard: { min_priority: 7, description: "Important axioms (~12 axioms)" },
      full: { min_priority: 0, description: "All axioms (32 axioms)" }
    }.freeze

    class << self
      # Unified entry point: runs Smells + Violations + BugHunting and merges results
      def analyze_all(code, path: nil)
        results = { smells: [], violations: [], bugs: [], summary: {} }

        if defined?(Smells)
          results[:smells] = Smells.analyze(code, path) rescue []
        end

        if defined?(Violations)
          v = Violations.analyze(code, path: path) rescue {}
          results[:violations] = (v[:literal] || []) + (v[:conceptual] || [])
        end

        if defined?(BugHunting)
          report = BugHunting.analyze(code, file_path: path || 'inline') rescue {}
          results[:bugs] = report.is_a?(Hash) ? report : []
        end

        total = results[:smells].size + results[:violations].size
        results[:summary] = { smells: results[:smells].size, violations: results[:violations].size, total: total }
        Result.ok(results)
      end

      # Basic structural scan - long methods, god classes, deep nesting
      # Now supports profile parameter for axiom filtering
      def quality_scan(path, profile: :standard, silent: false)
        Logging.dmesg_log('code_review', message: 'ENTER code_review.scan')
        return Result.err('Path not found') unless File.exist?(path)

        axioms = load_axioms_for_profile(profile)
        puts UI.dim("Scanning with #{profile} profile (#{axioms.size} axioms)...") if axioms && !silent

        files = Analyzers::FileCollector.ruby_files(path)
        issues = files.flat_map { |f| scan_file(f) }

        Result.ok(issues)
      end

      alias scan quality_scan # deprecated: use quality_scan

      # Deep scan - adds smell analysis and cyclic dependency detection
      def deep_quality_scan(path)
        return Result.err('Path not found') unless File.exist?(path)

        issues = []
        files = Analyzers::FileCollector.ruby_files(path)

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
        if File.directory?(path) && defined?(Smells) && Smells.respond_to?(:cyclic_deps?)
          cycle = begin; Smells.cyclic_deps?(files); rescue StandardError => e; Logging.warn("CodeReview", "cyclic_deps check failed: #{e.message}"); nil; end
          issues << { file: path, type: :cyclic_dependency, cycle: cycle[:cycle] } if cycle
        end

        Result.ok(issues.uniq { |i| [i[:file], i[:type] || i[:smell], i[:line]] })
      end

      alias deep_scan deep_quality_scan # deprecated: use deep_quality_scan

      # Quick scan - fast summary stats without detailed analysis
      def quick_quality_scan(path)
        return Result.err('Path not found') unless File.exist?(path)

        files = Analyzers::FileCollector.ruby_files(path)

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

      alias quick_scan quick_quality_scan # deprecated: use quick_quality_scan

      # Scan with specific focus areas
      def focused_scan(path, focus: [:complexity, :duplication, :security])
        return Result.err('Path not found') unless File.exist?(path)

        issues = []
        files = Analyzers::FileCollector.ruby_files(path)

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
            bugs = BugHunting.analyze(content, file_path: file) rescue []
            issues += (bugs.is_a?(Hash) ? bugs[:findings]&.values&.flatten || [] : [bugs]).select { |b| b.is_a?(Hash) }.map { |b| b.merge(file: file, type: :security) }
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

      def load_axioms_for_profile(profile)
        return nil unless SCAN_PROFILES.key?(profile)

        config = SCAN_PROFILES[profile]
        min_priority = config[:min_priority]

        axioms_path = File.join(MASTER.root, 'data', 'axioms.yml')
        return nil unless File.exist?(axioms_path)

        all_axioms = YAML.safe_load_file(axioms_path)
        all_axioms.select { |a| (a['priority'] || a[:priority] || 5) >= min_priority }
      rescue StandardError => e
        UI.warn("Failed to load axioms: #{e.message}")
        nil
      end

      # Scan individual file for basic structural issues
      def scan_file(path)
        content = File.read(path)
        issues = []

        # Long methods
        methods = Analyzers::MethodLengthAnalyzer.scan(content)
        methods.each do |method|
          if method[:length] > MAX_METHOD_LINES
            issues << {
              file: path,
              type: :long_method,
              lines: method[:length],
              severity: method[:length] > 50 ? :high : :medium,
              message: "Method has #{method[:length]} lines (max: #{MAX_METHOD_LINES})"
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
        max_nesting = Analyzers::NestingAnalyzer.depth(content)
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
      rescue StandardError => e
        [{ file: path, type: :error, message: e.message, severity: :low }]
      end
    end
  end

  Engine = CodeQuality # deprecated: use CodeQuality
end
