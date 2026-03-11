# frozen_string_literal: true

module Master3
  module Tools
    class StrReplace
      TIER        = :guarded
      NAME        = "str_replace"
      DESCRIPTION = "Replace unique string in a file. Fails if pattern matches 0 or 2+ times."

      def initialize(root:, undo:, governor:, event_bus: nil)
        @root     = File.realpath(root)
        @undo     = undo
        @governor = governor
        @bus      = event_bus
      end

      def call(path:, old_string:, new_string:)
        resolved = resolve(path)
        return resolved if resolved.err?

        full    = resolved.value!
        return Result.err("not found: #{path}", category: :validation) unless File.exist?(full)

        content = File.read(full)
        count   = content.scan(Regexp.quote(old_string)).size

        return Result.err("str_replace: pattern not found in #{path}", category: :validation) if count == 0
        return Result.err("str_replace: pattern matches #{count} times in #{path} (must be unique)", category: :validation) if count > 1

        perm = @governor.permit?(NAME, TIER, path)
        return perm if perm.err?

        @undo.snapshot(full)

        tmp = "#{full}.tmp.#{Process.pid}"
        begin
          File.write(tmp, content.sub(old_string, new_string))
          File.rename(tmp, full)
        ensure
          File.delete(tmp) if File.exist?(tmp) rescue nil
        end

        @bus&.publish("tool:after", tool: NAME, path:)
        Result.ok(full)
      rescue => e
        Result.err("str_replace: #{e.message}", category: :unknown)
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
