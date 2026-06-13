# frozen_string_literal: true

module Master
  module Reach
    # ReadFile — read file contents with line-range support and undo tracking.
    class ReadFile
      include PathGuard
      TIER = :safe
      MAX_LINES = 2000
      NAME = "read_file".freeze
      DESCRIPTION = "Read a file with line numbers. Guarded to project root.".freeze

      def initialize(root:, undo:, event_bus: nil)
        @root = File.realpath(root)
        @undo = undo
        @bus = event_bus
        @cache = {}
      end

      # Clear per-turn cache — called by Agent at the start of each chat turn.
      def reset!
        @cache.clear
      end

      def call(path:, offset: 0, limit: MAX_LINES)
        key = [path, offset, limit]
        return @cache[key] if @cache.key?(key)
        return resolved if resolved.err?

        full_path = resolved.value!
        return Result.err("not found: #{path}", category: :validation) unless File.exist?(full_path)

        lines = File.readlines(full_path)
        total = lines.size
        slice = lines[offset, limit] || []

        numbered = slice.each_with_index.map { |l, i| "#{offset + i + 1}\t#{l}" }.join
        suffix = total > offset + limit ? "\n[...truncated, #{total} total lines]" : ""

        result = Result.ok(numbered + suffix)
        @cache[key] = result
        result
      end

      private

    end
  end
end
