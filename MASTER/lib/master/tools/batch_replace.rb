# frozen_string_literal: true

module Master
  module Tools
    # Replace — batch find-and-replace across files in a directory.
    # Wraps pub4/sh/replace.sh with structured input/output.
    # TIER :guarded — modifies files, requires approval unless auto mode.
    class BatchReplace
      TIER        = :guarded
      NAME        = "replace"
      DESCRIPTION = "Find and replace text across all files in a directory."

      def initialize(root:, governor:, event_bus: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
        @script   = File.expand_path("../../../../../../sh/replace.sh", __dir__)
      end

      def call(old_str:, new_str:, dir: nil, rename_files: false)
        perm = @governor.permit?(NAME, TIER, "#{old_str} → #{new_str}")
        return perm if perm.err?

        target = dir ? File.expand_path(dir, @root) : @root
        return Result.err("replace: directory not found: #{target}", category: :validation) unless Dir.exist?(target)

        @bus&.publish("tool:before", tool: NAME, old: old_str, new: new_str)

        flags  = rename_files ? ["-f"] : []
        args   = flags + [old_str, new_str, target]
        out, err, status = Open3.capture3("zsh", @script, *args)

        @bus&.publish("tool:after", tool: NAME)

        if status.success?
          changed = out.lines.count { |l| l.start_with?("Updated:", "Renamed:") }
          Result.ok("replaced #{changed} file(s)\n#{out.strip}")
        else
          Result.err("replace: #{err.strip.empty? ? out.strip : err.strip}", category: :unknown)
        end
      rescue => e
        Result.err("replace: #{e.message}", category: :unknown)
      end
    end
  end
end
