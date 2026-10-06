# frozen_string_literal: true

require "fileutils"

module Master
  module Io
    # DeletePath — remove a file or directory inside the workspace.
    #
    # Files are journaled through Trace::Undo before removal. A directory is
    # journaled file-by-file, so undo can recreate its contents without giving
    # delete a bypass around the normal write boundary.
    class DeletePath
      include PathGuard

      NAME = "delete_path".freeze
      TIER = :dangerous
      DESCRIPTION = "Delete a file or directory under the workspace; recursive directory deletion is explicit.".freeze

      def initialize(root:, undo:, governor:, event_bus: nil)
        @root = File.realpath(root)
        @undo = undo
        @governor = governor
        @bus = event_bus
      end

      def call(path:, recursive: false)
        resolved = resolve(path)
        return resolved if resolved.err?

        full = resolved.value!
        return Result.err("not found: #{path}", category: :validation) unless File.exist?(full) || Dir.exist?(full)

        permit = @governor.permit?(NAME, TIER, "#{recursive ? "delete recursively" : "delete"} #{path}")
        return permit if permit.err?

        entries =
          if File.file?(full)
            [full]
          elsif recursive
            Dir.glob(File.join(full, "**", "*"), File::FNM_DOTMATCH).select { |entry| File.file?(entry) }.sort
          else
            return Result.err("directory not empty: #{path}; pass recursive=true to delete its contents",
                              category: :validation) unless Dir.children(full).empty?
            []
          end

        protected = entries.filter_map do |entry|
          rel = entry.delete_prefix(@root + File::SEPARATOR)
          rel if PathGuard.secret?(entry) || sacred?(rel)
        end
        return Result.err("protected path refused: #{protected.first}", category: :validation) unless protected.empty?

        entries.each do |entry|
          snapshot = @undo&.snapshot(entry)
          return snapshot if snapshot&.err?
        end

        if File.file?(full)
          File.delete(full)
        else
          Dir.delete(full)
        end

        @bus&.publish("tool:after", tool: NAME, path:, op: "delete", count: entries.size + 1)
        Result.ok(path)
      rescue SystemCallError => e
        Result.err("delete_path: #{e.message}", category: :infrastructure)
      rescue StandardError => e
        Result.err("delete_path: #{e.message}", category: :unknown)
      end

      private

      def sacred?(rel)
        master_relative = @root == Master::REPO_ROOT ? rel.delete_prefix("MASTER/") : rel
        Master::Ground::Immutability.blocked?(master_relative, root: Master::ROOT) ||
          SACRED_PATHS.any? do |path|
            sacred = path.chomp("/")
            master_relative == sacred || master_relative.start_with?("#{sacred}/")
          end
      end
    end
  end
end
