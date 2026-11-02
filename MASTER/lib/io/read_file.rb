# frozen_string_literal: true

require "digest"

module Master
  module Io
    # ReadFile — read file contents with line-range support and undo tracking.
    class ReadFile
      include PathGuard
      TIER = :safe
      MAX_LINES = 2000
      NAME = "read_file".freeze
      DESCRIPTION = "Read a file with line numbers and a whole-file SHA-256 receipt. Guarded to project root; full=true reads every line.".freeze

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
        # A cached slice is reusable only when the backing read belongs to
        # this turn and its bytes/age remain fresh.
        receipt_fresh = if @ground_truth&.respond_to?(:fresh_in_current_turn?)
                          @ground_truth.fresh_in_current_turn?(full_path)
                        else
                          !@ground_truth || @ground_truth.fresh?(full_path)
                        end
        return @cache[key] if @cache.key?(key) && receipt_fresh
        return Result.err("not found: #{path}", category: :validation) unless File.exist?(full_path)

        formatted = format_file_slice(full_path, offset:, limit:, hashline:, full:)
        return formatted if formatted.is_a?(Result) && formatted.err?

        result = Result.ok(formatted)
        @cache[key] = result
        result
      end

      private

      def format_file_slice(full_path, offset:, limit:, hashline:, full:)
        lines = File.readlines(full_path)
        content = lines.join
        digest = Digest::SHA256.hexdigest(content)
        if @ground_truth && !@ground_truth.record_read!(full_path, content:)
          return Result.err("read completed but its ground-truth receipt could not be recorded", category: :infrastructure)
        end
        total = lines.size
        slice = limit ? (lines[offset, limit] || []) : (lines[offset..] || [])

        numbered =
          if hashline
            Hashline.format_lines(slice, offset:)
          else
            slice.each_with_index.map { |l, i| "#{offset + i + 1}\t#{l}" }.join
          end
        suffix = limit && total > offset + limit ? "\n[...truncated, #{total} total lines]" : ""
        output = "#{numbered}#{suffix}"
        output << "\n" unless output.empty? || output.end_with?("\n")
        output << "[read receipt: sha256=#{digest} bytes=#{content.bytesize} lines=#{total} shown=#{slice.size} offset=#{offset} scope=whole_file]"
      end
    end
  end
end
