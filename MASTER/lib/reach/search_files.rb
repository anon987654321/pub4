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
        @bus = event_bus
        @cache = {}
      end

      def reset! = @cache.clear

      def call(pattern:, glob: "**/*", context_lines: 2)
        key = [pattern, glob, context_lines]
        return @cache[key] if @cache.key?(key)

        regexp = Regexp.new(pattern)
        results = collect_results(cached_paths(glob), regexp, context_lines)
        @cache[key] = Result.ok(format_results(results))
      rescue RegexpError
        Result.err("invalid pattern: #{pattern}", category: :validation)
      rescue StandardError => e
        Result.err("search_files: #{e.message}", category: :unknown)
      end

      private

      def collect_results(paths, regexp, context_lines)
        results = []
        paths.each do |path|
          next if binary_file?(path)

          results.concat(file_results(path, regexp, context_lines, MAX_RESULTS - results.size))
          break if results.size >= MAX_RESULTS
        end
        results
      end

      def file_results(path, regexp, context_lines, limit)
        lines = File.readlines(path)
        matches = lines.each_index.filter_map do |index|
          next unless lines[index].match?(regexp)

          format_match(path, lines, index, context_lines)
        end
        matches.first(limit)
      end

      def format_match(path, lines, index, context_lines)
        first = [index - context_lines, 0].max
        last = [index + context_lines, lines.size - 1].min
        snippet = lines[first..last].each_with_index.map { |line, offset| "#{first + offset + 1}:#{line}" }.join
        relative = path.delete_prefix(@root + "/")
        "#{relative}:#{index + 1}\n#{snippet}"
      end

      def format_results(results)
        return "(no matches)" if results.empty?

        suffix = results.size >= MAX_RESULTS ? "\n[...truncated]" : ""
        results.join("\n---\n") + suffix
      end

      def cached_paths(glob)
        key = [:glob, glob]
        @cache[key] ||= Dir.glob(File.join(@root, glob)).select { |path| File.file?(path) }
      end

      def binary_file?(path)
        File.read(path, BINARY_SAMPLE_BYTES).include?("\x00")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "search_files.binary_file", event_bus: @bus, path:)
        true
      end
    end
  end
end
