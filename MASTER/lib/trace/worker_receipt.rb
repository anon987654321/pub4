# frozen_string_literal: true

require "securerandom"

module Master
  module Trace
    # A durable before- and after-record around one unit of background work: a
    # heartbeat job, a steward's mission run, a standing order. Nobody watches
    # these as they run, so the before-record must land before the work starts,
    # and a crash leaves a before with no after that names what was cut short.
    # The after-record is best effort: the work has happened by then, and
    # failing it would only hide that.
    module WorkerReceipt
      BEFORE = "worker:before"
      AFTER = "worker:after"

      module_function

      def around(bus, worker:, job:)
        return yield unless bus.respond_to?(:publish_required)

        id = SecureRandom.uuid
        bus.publish_required(BEFORE, worker: worker.to_s, job: job.to_s, invocation_id: id, pid: Process.pid)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
        outcome = "error"
        result = yield
        outcome = succeeded?(result) ? "success" : "error"
        result
      ensure
        if id
          elapsed_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - started.to_i
          bus.publish(AFTER, worker: worker.to_s, job: job.to_s, invocation_id: id, status: outcome, elapsed_ms:)
        end
      end

      def succeeded?(result)
        return result.ok? if result.respond_to?(:ok?)

        !result.to_s.start_with?("error")
      end
    end
  end
end
