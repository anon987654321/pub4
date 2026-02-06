# frozen_string_literal: true

module MASTER
  module Engine
    MAX_METHOD_LINES = 20
    MAX_FILE_LINES = 300

    class << self
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

      def deep_scan(path)
        return Result.err('Path not found') unless File.exist?(path)

        issues = []

        if File.directory?(path)
          files = Dir[File.join(path, '**', '*.rb')]
          files.each do |f|
            content = File.read(f) rescue next
            issues += scan_file(f)
            issues += Smells.analyze(content, f).map { |s| s.merge(file: f) }
          end

          # Check for cyclic dependencies
          cycle = Smells.cyclic_deps?(files)
          issues << { file: path, type: :cyclic_dependency, cycle: cycle[:cycle] } if cycle
        else
          content = File.read(path)
          issues = scan_file(path)
          issues += Smells.analyze(content, path).map { |s| s.merge(file: path) }
        end

        Result.ok(issues.uniq { |i| [i[:file], i[:type] || i[:smell], i[:line]] })
      end

      def quick_scan(path)
        return Result.err('Path not found') unless File.exist?(path)

        files = File.directory?(path) ? Dir[File.join(path, '**', '*.rb')] : [path]
        
        {
          files: files.size,
          total_lines: files.sum { |f| File.read(f).lines.size rescue 0 },
          long_files: files.count { |f| (File.read(f).lines.size rescue 0) > 300 },
          principles: Principle.load_all.size,
          patterns: Smells.all_patterns.size
        }
      end

      private

      def scan_file(path)
        content = File.read(path)
        issues = []

        # Long methods
        content.scan(/def \w+.*?^  end/m).each do |method|
          if method.lines.size > MAX_METHOD_LINES
            issues << { file: path, type: :long_method, lines: method.lines.size }
          end
        end

        # God class
        if content.lines.size > MAX_FILE_LINES
          issues << { file: path, type: :god_class, lines: content.lines.size }
        end

        # Deep nesting
        if Smells.deep_nesting?(content)
          issues << { file: path, type: :deep_nesting }
        end

        issues
      rescue => e
        [{ file: path, type: :error, message: e.message }]
      end
    end
  end
end
