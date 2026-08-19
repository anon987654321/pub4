# frozen_string_literal: true

require_relative "process_budget"

module Master
  module Ops
    # At most one *slot* loop (autofix/watch/watcher) may run at a time. The loops
    # and their env flags are not defined here — they come from the single source,
    # data/limits.yml#process, via ProcessBudget. LoopSlot is only the mutual-exclusion
    # view over the slot loops; the background heartbeat is non-slot and excluded.
    module LoopSlot
      module_function

      def flags
        ProcessBudget.env_by_loop.select { |name, _env| ProcessBudget.slot_loop?(name) }
      end

      def enabled
        ProcessBudget.active_loops
      end

      def selected
        enabled.first
      end

      def valid?
        enabled.size <= 1
      end

      def status
        {
          selected:,
          enabled:,
          valid: valid?,
          flags: flags.transform_values { |env| ENV.fetch(env, "0") },
        }
      end

      def validate!
        return true if valid?

        raise ArgumentError,
              "Set exactly one loop: MASTER_LOOP=fix|watch|watcher or MASTER_AUTOFIX=1, MASTER_WATCH=1, MASTER_WATCHER=1."
      end
    end
  end
end
