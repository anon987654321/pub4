# frozen_string_literal: true

module Master3
  module Swarm
    # Orchestrates specialized workers on a need-to-know basis.
    # The coordinator sees everything; workers see only their context slice.
    class Coordinator
      WORKER_CLASSES = {
        analyst:    Workers::Analyst,
        coder:      Workers::Coder,
        reviewer:   Workers::Reviewer,
        researcher: Workers::Researcher
      }.freeze

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
        @workers = {}
      end

      # Run a single worker with a curated context slice
      def dispatch(role, task:, context_slice: {})
        worker = worker_for(role) or return Result.err("unknown role: #{role}")
        @bus&.publish(:swarm_dispatch, role:, task: task[0..60])
        worker.call(task:, context_slice:)
      end

      # Run analysis → review pipeline (most common pattern)
      # Worker 1 (analyst) sees only the file. Worker 2 (reviewer) sees only the code.
      def analyse_and_review(file_path:, code:)
        analysis = dispatch(:analyst,
                            task: "identify all issues",
                            context_slice: { file: file_path, code: code })
        return analysis unless analysis.ok?

        review = dispatch(:reviewer,
                          task: "security and correctness review",
                          context_slice: { code: code })
        return review unless review.ok?

        Result.ok({
          analysis: analysis.value!,
          review:   review.value!,
          approved: review.value!["approved"]
        })
      end

      # Fan-out: run multiple workers in parallel threads, collect results
      def fan_out(tasks)
        # tasks: [{role:, task:, context_slice:}, ...]
        threads = tasks.map do |t|
          Thread.new { [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))] }
        end
        results = threads.map(&:value).to_h
        Result.ok(results)
      end

      def worker_roles = WORKER_CLASSES.keys

      private

      def worker_for(role)
        sym = role.to_sym
        @workers.fetch(sym) do
          klass = WORKER_CLASSES[sym]
          return nil unless klass
          @workers[sym] = klass.new(agent: @agent, event_bus: @bus)
        end
      end
    end
  end
end
