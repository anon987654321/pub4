# frozen_string_literal: true

require "fileutils"

module Master
  module Tools
    class WriteFile
      TIER        = :guarded
      NAME        = "write_file"
      DESCRIPTION = "Atomically write content to a file, with undo snapshot."

      def initialize(root:, undo:, governor:, event_bus: nil)
        @root     = File.realpath(root)
        @undo     = undo
        @governor = governor
        @bus      = event_bus
      end

      def call(path:, content:)
        resolved = resolve(path)
        return resolved if resolved.err?

        full = resolved.value!
        perm = @governor.permit?(NAME, TIER, path)
        return perm if perm.err?

        @undo.snapshot(full)
        FileUtils.mkdir_p(File.dirname(full))

        tmp = "#{full}.tmp.#{Process.pid}"
        File.write(tmp, content)
        File.rename(tmp, full)

        @bus&.publish("tool:after", tool: NAME, path:)
        Result.ok(full)
      rescue => e
        File.delete(tmp) if tmp && File.exist?(tmp)
        Result.err("write_file: #{e.message}", category: :unknown)
      end

      private

      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless full.start_with?(@root)
        Result.ok(full)
      end
    end
  end
end
