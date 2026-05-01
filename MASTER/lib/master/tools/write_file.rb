# frozen_string_literal: true

require "fileutils"

module Master
  module Tools
    class WriteFile
      include PathGuard
      TIER        = :guarded
      NAME        = "write_file".freeze
      DESCRIPTION = "Atomically write content to a file, with undo snapshot.".freeze

      def initialize(root:, undo:, governor:, event_bus: nil, diff_stager: nil)
        @root        = File.realpath(root)
        @undo        = undo
        @governor    = governor
        @bus         = event_bus
        @diff_stager = diff_stager
      end

      def call(path:, content:)
        resolved = resolve(path)
        return resolved if resolved.err?

        full = resolved.value!
        perm = @governor.permit?(NAME, TIER, path)
        return perm if perm.err?

        return @diff_stager.stage(path: full, new_content: content, tool: NAME) if @diff_stager

        @undo.snapshot(full)
        FileUtils.mkdir_p(File.dirname(full))

        tmp_path = "#{full}.tmp.#{Process.pid}"
        File.write(tmp_path, content)
        File.rename(tmp_path, full)

        @bus&.publish("tool:after", tool: NAME, path:)
        Result.ok(full)
      rescue StandardError => e
        File.delete(tmp_path) if tmp_path && File.exist?(tmp_path)
        Result.err("write_file: #{e.message}", category: :unknown)
      end

    end
  end
end
