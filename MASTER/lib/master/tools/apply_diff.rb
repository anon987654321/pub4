# frozen_string_literal: true

require "open3"

module Master
  module Tools
    class ApplyDiff
      TIER        = :guarded
      NAME        = "apply_diff"
      DESCRIPTION = "Apply a unified diff patch to files in the project."

      def initialize(root:, undo:, governor:, event_bus: nil)
        @root     = File.realpath(root)
        @undo     = undo
        @governor = governor
        @bus      = event_bus
      end

      def call(diff:)
        perm = @governor.permit?(NAME, TIER, "apply patch")
        return perm if perm.err?

        affected = diff.scan(/^--- a\/(.+)$/).flatten + diff.scan(/^\+\+\+ b\/(.+)$/).flatten
        affected.uniq.each { |p| @undo.snapshot(File.join(@root, p)) }

        out, err, status = Open3.capture3("patch -p1", stdin_data: diff, chdir: @root)
        return Result.err("apply_diff: #{err.strip}", category: :unknown) unless status.success?

        @bus&.publish("tool:after", tool: NAME)
        Result.ok(out.strip)
      rescue => e
        Result.err("apply_diff: #{e.message}", category: :unknown)
      end
    end
  end
end
