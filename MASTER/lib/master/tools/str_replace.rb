# frozen_string_literal: true

module Master
  module Tools
    # StrReplace — surgical string replacement in files with undo support.
    class StrReplace
        include PathGuard
      TIER        = :guarded
      NAME        = "str_replace".freeze
      DESCRIPTION = "Replace unique string in a file. Fails if pattern matches 0 or 2+ times."

      def initialize(root:, undo:, governor:, event_bus: nil, diff_stager: nil)
        @root        = File.realpath(root)
        @undo        = undo
        @governor    = governor
        @bus         = event_bus
        @diff_stager = diff_stager
      end

      def call(path:, old_string:, new_string:)
        resolved = resolve(path)
        return resolved if resolved.err?

        full    = resolved.value!
        return Result.err("not found: #{path}", category: :validation) unless File.exist?(full)

        content = File.read(full)
        count   = content.scan(Regexp.quote(old_string)).size

        return Result.err("str_replace: pattern not found in #{path}", category: :validation) if count.zero?
        return Result.err("str_replace: pattern matches #{count} times in #{path} (must be unique)", category: :validation) if count > 1

        perm = @governor.permit?(NAME, TIER, path)
        return perm if perm.err?

        new_content = content.sub(old_string, new_string)

        if @diff_stager
          return @diff_stager.stage(path: full, new_content:, tool: NAME)
        end

        @undo.snapshot(full)

        tmp = "#{full}.tmp.#{Process.pid}"
        File.write(tmp, new_content)
        File.rename(tmp, full)

        @bus&.publish("tool:after", tool: NAME, path:)
        Result.ok(full)
      rescue StandardError => e
        File.delete(tmp) if tmp && File.exist?(tmp)
        Result.err("str_replace: #{e.message}", category: :unknown)
      end

      private

    end
  end
end
