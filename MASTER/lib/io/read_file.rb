# frozen_string_literal: true

module Master
  module Io
    # ReadFile — read file contents with line-range support and undo tracking.
    class ReadFile
      include PathGuard
      TIER = :safe
      MAX_LINES = 2000
      NAME = "read_file".freeze
      DESCRIPTION = "Read a file with line numbers. Guarded to project root.".freeze

      def initialize(root:, undo:, event_bus: nil, ground_truth: nil)
        @root = File.realpath(root)
        @undo = undo
        @bus = event_bus
        @ground_truth = ground_truth
        @cache = {}
      end

      # Clear per-turn cache — called by Agent at the start of each chat turn.
      def reset!
        @cache.clear
      end

      def call(path:, offset: 0, limit: MAX_LINES, hashline: false)
        key = [path, offset, limit, hashline]
        return @cache[key] if @cache.key?(key)
        resolved = resolve(path)
        return resolved if resolved.err?

        full_path = resolved.value!
        return Result.err("not found: #{path}", category: :validation) unless File.exist?(full_path)

        result = Result.ok(format_file_slice(full_path, offset:, limit:, hashline:))
        @cache[key] = result
        result
      end

      private

      def format_file_slice(full_path, offset:, limit:, hashline:)
        lines = File.readlines(full_path)
        @ground_truth&.record_read!(full_path, content: lines.join)
        total = lines.size
        slice = lines[offset, limit] || []

        numbered =
          if hashline
            Hashline.format_lines(slice, offset:)
          else
            slice.each_with_index.map { |l, i| "#{offset + i + 1}\t#{l}" }.join
          end
        suffix = total > offset + limit ? "\n[...truncated, #{total} total lines]" : ""
        numbered + suffix
      end
    end
  end
end
