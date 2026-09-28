# frozen_string_literal: true

module Master
  module Io
    class ListDir
      TIER = :safe
      NAME = "list_dir".freeze
      DESCRIPTION = "List directory contents, depth-limited.".freeze
      MAX_DEPTH = 5
      MAX_ENTRIES = 2_000

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus = event_bus
      end

      def call(path: ".", depth: 2, pattern: nil)
        resolved = resolve(path)
        return resolved if resolved.err?

        full = resolved.value!
        depth = depth.to_i.clamp(0, MAX_DEPTH)
        state = { seen: 0, truncated: false }
        lines = list_tree(dir: full, depth:, pattern:, state:)
        lines << "... (max entries reached)" if state[:truncated]
        Result.ok(lines.join("\n"))
      end

      private

      def list_tree(dir:, depth:, pattern:, state:, indent: 0)
        return [] if depth < 0 || state[:truncated]

        entries = Dir.entries(dir).reject { |entry| entry.start_with?(".") }.sort_by do |entry|
          [File.directory?(File.join(dir, entry)) ? 0 : 1, entry]
        end

        entries.flat_map do |entry|
          next [] if pattern && !File.fnmatch?(pattern, entry)
          if state[:seen] >= MAX_ENTRIES
            state[:truncated] = true
            break []
          end

          full = File.join(dir, entry)
          prefix = "  " * indent
          state[:seen] += 1

          if File.directory?(full)
            ["#{prefix}#{entry}/"] + list_tree(dir: full, depth: depth - 1, pattern:, state:, indent: indent + 1)
          else
            ["#{prefix}#{entry}"]
          end
        end
      end

      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless PathGuard.inside_real_root?(full, @root)
        return Result.err("not a directory: #{path}", category: :validation) unless File.directory?(full)
        Result.ok(full)
      end
    end
  end
end
