# frozen_string_literal: true

module Master
  module Io
    class SearchFiles
      TIER = :safe
      NAME = "search_files".freeze
      DESCRIPTION = "Search for a pattern in files under the project root.".freeze
      MAX_RESULTS = 200
      BINARY_SAMPLE_BYTES = 512

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus = event_bus
      end

      def reset! = self

      # `path` is a glob under the root too; a repo-relative `MASTER/lib/x.rb` means `lib/x.rb` when the root is
      # MASTER, so a model that thinks from the repo root finds its file instead of an empty result.
      def call(pattern:, glob: "**/*", context_lines: 2, path: nil)
        regexp = Regexp.new(pattern)
        glob = relative_glob(path || glob)

        paths = current_paths(glob)
        results = collect_results(paths, regexp, context_lines)
        Result.ok(format_results(results, searched: paths.size, glob:))
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

      def format_results(results, searched:, glob:)
        return no_match_line(searched, glob) if results.empty?

        suffix = results.size >= MAX_RESULTS ? "\n[...truncated]" : ""
        results.join("\n---\n") + suffix
      end

      # An empty result must say what it searched, so it can be told from a search that looked in the wrong place.
      def no_match_line(searched, glob)
        return "(no matches in #{searched} files for #{glob})" if searched.positive?

        "(no files matched #{glob} under #{File.basename(@root)}; globs are relative to #{File.basename(@root)})"
      end

      # A directory names its whole tree: the model-facing tool passes `path` (default ".") here,
      # and a glob of a directory alone matches no file.
      def relative_glob(glob)
        prefix = "#{File.basename(@root)}/"
        relative = glob.to_s.start_with?(prefix) ? glob.to_s.delete_prefix(prefix) : glob.to_s
        return relative unless File.directory?(File.join(@root, relative))

        [".", ""].include?(relative.chomp("/")) ? "**/*" : File.join(relative.chomp("/"), "**", "*")
      end

      def current_paths(glob)
        Dir.glob(File.join(@root, glob)).select { |path| searchable?(path) }
      end

      # A glob can climb with `..` and a hit can be a symlink out of the root,
      # so every hit is checked by its realpath rather than by the pattern.
      def searchable?(path)
        return false unless File.file?(path)
        return false unless PathGuard.inside_real_root?(File.expand_path(path), @root)

        canonical = File.realpath(path)
        PathGuard.inside_root?(canonical, @root) && !PathGuard.secret?(canonical)
      rescue SystemCallError
        false
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
