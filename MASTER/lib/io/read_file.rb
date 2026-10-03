# frozen_string_literal: true

module Master
  module Io
    # ReadFile — read file contents with line-range support and undo tracking.
    class ReadFile
      include PathGuard
      TIER = :safe
      MAX_LINES = 2000
      NAME = "read_file".freeze
      DESCRIPTION = "Read a file with line numbers. Guarded to project root; full=true reads every line.".freeze

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

      def call(path:, offset: 0, limit: MAX_LINES, hashline: false, full: false)
        # Normal reads stay bounded so an accidental giant file cannot consume
        # the turn. `full: true` is the explicit escape hatch for audits,
        # snapshots and files whose complete contents are required.
        offset = [offset.to_i, 0].max
        limit = full ? nil : limit.to_i.clamp(1, MAX_LINES)
        key = [path, offset, limit, hashline, full]
        resolved = resolve(path, write: false)
        return resolved if resolved.err?

        full_path = resolved.value!
        # A file changed since its last read is read again: WriteFile refuses it
        # until it is, so a cached copy would refuse the write for the whole turn.
        return @cache[key] if @cache.key?(key) && !@ground_truth&.changed_since_read?(full_path)
        return Result.err("not found: #{path}", category: :validation) unless File.exist?(full_path)

        result = Result.ok(format_file_slice(full_path, offset:, limit:, hashline:, full:))
        @cache[key] = result
        result
      end

      private

      def format_file_slice(full_path, offset:, limit:, hashline:, full:)
        lines = File.readlines(full_path)
        @ground_truth&.record_read!(full_path, content: lines.join)
        total = lines.size
        slice = limit ? (lines[offset, limit] || []) : (lines[offset..] || [])

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
