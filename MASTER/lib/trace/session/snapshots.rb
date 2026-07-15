# frozen_string_literal: true

module Master
  module Trace
    class Session
      # In-memory per-path content snapshots (not persisted to disk) —
      # separate from Session's own message/cost/save-load concerns.
      module Snapshots
        def snapshot(path, content)
          @mutex.synchronize do
            @snapshots[path] ||= []
            @snapshots[path] << content
          end
        end

        def last_snapshot(path)
          @mutex.synchronize { @snapshots[path]&.last }
        end
      end
    end
  end
end
