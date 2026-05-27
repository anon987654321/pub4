# frozen_string_literal: true

module Master
  module Reach
    class SearchFiles
      TIER = :safe
      NAME = "search_files".freeze
      DESCRIPTION = "Search for a pattern in files under the project root.".freeze
      MAX_RESULTS = 200
      BINARY_SAMPLE_BYTES = 512

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus  = event_bus
        @cache = {}
      end

      def reset!
        @cache.clear
      end

      def call(pattern:, glob: "**/*", context_lines: 2)
        key = [pattern, glob, context_lines]
        return @cache[key] if @cache.key?(key)
        begin
          re = Regexp.new(pattern)
        rescue RegexpError; return Result.err("invalid pattern: #{pattern}", category: :validation)
        end

        paths   = cached_paths(glob)
        results = []

        paths.each do |path|
          next if binary_file?(path)

          lines = File.readlines(path)
          lines.each_with_index do |line, idx|
            next unless line.match?(re)
            start  = [idx - context_lines, 0].max
            finish = [idx + context_lines, lines.size - 1].min
            ctx    = lines[start..finish].each_with_index.map { |l, i| "#{start + i + 1}:#{l}" }.join
            rel    = path.delete_prefix(@root + "/")
            results << "#{rel}:#{idx + 1}\n#{ctx}"
            if results.size >= MAX_RESULTS
              out = Result.ok(results.join("\n---\n") + "\n[...truncated]")
              @cache[key] = out
              return out
            end
          end
        end

        out = Result.ok(results.empty? ? "(no matches)" : results.join("\n---\n"))
        @cache[key] = out
        out
      rescue StandardError => e
        Result.err("search_files: #{e.message}", category: :unknown)
      end

      private

      def cached_paths(glob)
        list_key = [:glob, glob]
        return @cache[list_key] if @cache.key?(list_key)
        paths = Dir.glob(File.join(@root, glob)).select { |p| File.file?(p) }
        @cache[list_key] = paths
      end

      def binary_file?(path)
        sample = begin
          File.read(path, BINARY_SAMPLE_BYTES)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "SearchFiles.binary_file?")
          ""
        end
        sample.include?("\x00")
      end
    end
  end
end
