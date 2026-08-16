# frozen_string_literal: true

module Master
  module Io
    # Shared boilerplate for mutating tools: governor permit, undo snapshot,
    # atomic write, bus publish — or stage via diff_stager when present.
    # Tool classes include Base, set NAME/TIER, and call commit_write inside safely.
    module Base
      include PathGuard
      include Master::Ground::AtomicWrite

      def permit(ctx = nil)
        @governor.permit?(self.class::NAME, self.class::TIER, ctx)
      end

      # Apply a write through the standard pipeline.
      # Returns Result.ok(full_path), or stages it when diff_stager wires staging.
      def commit_write(full, content, path: nil)
        content = WhitespaceNormalizer.normalize(content, path: full)
        written = path || full
        bytes = content.bytesize
        @bus&.publish("tool:before", tool: self.class::NAME, path: written, bytes:, op: "write")

        guard = Master::Review::Scan::WriteGuard.default.verdict(path: full, content:)
        @bus&.publish("write:guard", path: written, introduced: guard.introduced.size, blocked: guard.blocked?) unless guard.introduced.empty?
        return Result.err("write refused — #{guard.reason}", category: :policy) if guard.blocked?

        return @diff_stager.stage(path: full, new_content: content, tool: self.class::NAME) if @diff_stager

        @undo.snapshot(full)
        FileUtils.mkdir_p(File.dirname(full))
        write_atomic(full, content)
        Master::Trace::WriteTracker.current&.record(written)
        @bus&.publish("tool:after", tool: self.class::NAME, path: written, bytes:, op: "write")
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
