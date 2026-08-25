# frozen_string_literal: true

module Master
  module Autonomy
    class Recovery
      MAX_RETRIES = 3

      def initialize(store:, snapshots:)
        @store = store
        @snapshots = snapshots
      end

      def recover(goal_id:, task:, snapshot:, observation:)
        attempt = task.attempts + 1
        @store.append(goal_id, task.id, "task.failure", {
          attempt:,
          error: observation.message,
          rollback: false
        })

        rolled_back = @snapshots.rollback(snapshot)
        @store.append(goal_id, task.id, "task.rollback", { ok: rolled_back, snapshot: snapshot[:id] })

        state = attempt >= MAX_RETRIES ? :failed : :ready
        [task.with_state(state, attempts: attempt, payload: task.payload.merge(last_error: observation.message))]
      end
    end
  end
end
