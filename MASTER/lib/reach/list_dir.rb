# frozen_string_literal: true

module Master
  module Reach
    class ListDir
      TIER = :safe
      NAME = "list_dir".freeze
      DESCRIPTION = "List directory contents, depth-limited.".freeze
      MAX_DEPTH = 5

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus = event_bus
      end

      def call(path: ".", depth: 2, pattern: nil)
        resolved = resolve(path)
        return resolved if resolved.err?

        full = resolved.value!
        depth = [depth.to_i, MAX_DEPTH].min
        lines = list_tree(base: full, dir: full, depth:, pattern:)
        Result.ok(lines.join("\n"))
      end

      private

      def list_tree(base:, dir:, depth:, pattern:, indent: 0)
        return [] if depth < 0
        entries = Dir.entries(dir).reject { |e| e.start_with?(".") }.sort
        entries.flat_map do |entry|
          full = File.join(dir, entry)
          next [] if pattern && !File.fnmatch?(pattern, entry)
          prefix = "  " * indent
          if File.directory?(full)
            ["#{prefix}#{entry}/"] + list_tree(base:, dir: full, depth: depth - 1, pattern:, indent: indent + 1)
          else
            ["#{prefix}#{entry}"]
          end
        end
      end

      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)
        return Result.err("not a directory: #{path}", category: :validation) unless File.directory?(full)
        Result.ok(full)
      end
    end
  end
end
