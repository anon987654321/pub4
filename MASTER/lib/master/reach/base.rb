# frozen_string_literal: true

module Master
  module Reach
    # Shared boilerplate for mutating tools: governor permit, undo snapshot,
    # atomic write, bus publish — or stage via diff_stager when present.
    # Tool classes include Base, set NAME/TIER, and call commit_write inside safely.
    module Base
      include PathGuard
      include AtomicWrite

      def permit(ctx = nil)
        @governor.permit?(self.class::NAME, self.class::TIER, ctx)
      end

      # Apply a write through the standard pipeline.
      # Returns Result.ok(full_path), or stages it if diff_stager is wired.
      def commit_write(full, content, path: nil)
        return @diff_stager.stage(path: full, new_content: content, tool: self.class::NAME) if @diff_stager

        @undo.snapshot(full)
        FileUtils.mkdir_p(File.dirname(full))
        write_atomic(full, content)
        @bus&.publish("tool:after", tool: self.class::NAME, path: path || full)
        Result.ok(full)
      end

      def safely
        yield
      rescue StandardError => e
        Result.err("#{self.class::NAME}: #{e.message}", category: :unknown)
      end
    end
  end
end
