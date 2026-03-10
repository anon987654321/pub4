# frozen_string_literal: true

module Master3
  module Tools
    class SearchFiles
      TIER        = :safe
      NAME        = "search_files"
      DESCRIPTION = "Search for a pattern in files under the project root."
      MAX_RESULTS = 200

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus  = event_bus
      end

      def call(pattern:, glob: "**/*", context_lines: 2)
        re      = Regexp.new(pattern) rescue return Result.err("invalid pattern: #{pattern}", category: :validation)
        paths   = Dir.glob(File.join(@root, glob)).select { |p| File.file?(p) }
        results = []

        paths.each do |path|
          lines = File.readlines(path)
          lines.each_with_index do |line, idx|
            next unless line.match?(re)
            start  = [idx - context_lines, 0].max
            finish = [idx + context_lines, lines.size - 1].min
            ctx    = lines[start..finish].each_with_index.map { |l, i| "#{start + i + 1}:#{l}" }.join
            rel    = path.delete_prefix(@root + "/")
            results << "#{rel}:#{idx + 1}\n#{ctx}"
            return Result.ok(results.join("\n---\n") + "\n[...truncated]") if results.size >= MAX_RESULTS
          end
        end

        Result.ok(results.empty? ? "(no matches)" : results.join("\n---\n"))
      rescue => e
        Result.err("search_files: #{e.message}", category: :unknown)
      end
    end
  end
end
