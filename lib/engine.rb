# frozen_string_literal: true

module MASTER
  module Engine
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

      private

      def scan_file(path)
        content = File.read(path)
        issues = []

        # Long methods (>20 lines)
        content.scan(/def \w+.*?^  end/m).each do |method|
          if method.lines.size > 20
            issues << { file: path, type: :long_method, lines: method.lines.size }
          end
        end

        # God class (>300 lines)
        if content.lines.size > 300
          issues << { file: path, type: :god_class, lines: content.lines.size }
        end

        issues
      rescue => e
        [{ file: path, type: :error, message: e.message }]
      end
    end
  end
end
