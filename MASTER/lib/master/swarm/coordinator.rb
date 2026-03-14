# frozen_string_literal: true

module Master
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

      WORKER_TIMEOUT = 30  # seconds per worker

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

      # Fan-out: run multiple workers in parallel threads with per-worker timeout.
      # Returns {results: {role => Result}, synthesis: String}.
      def fan_out(tasks, timeout: WORKER_TIMEOUT)
        threads = tasks.map do |t|
          Thread.new do
            [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
          end
        end

        results = threads.map do |th|
          if th.join(timeout)
            th.value
          else
            th.kill rescue nil
            [:timeout, Result.err("worker timed out after #{timeout}s", category: :unknown)]
          end
        end.to_h

        synthesis = synthesize(results)
        @bus&.publish(:swarm_fan_out_done, roles: results.keys, synthesis: synthesis[0..200])
        Result.ok({ results: results, synthesis: synthesis })
      end

      def worker_roles = WORKER_CLASSES.keys

      private

      # Combine successful worker results into a coherent summary string.
      def synthesize(results)
        lines = results.filter_map do |role, r|
          next if role == :timeout
          next unless r.respond_to?(:ok?) && r.ok?
          val = r.value!
          text = val.is_a?(Hash) ? val.inspect : val.to_s
          "### #{role}\n#{text.strip}"
        end
        lines.empty? ? "(no results)" : lines.join("\n\n")
      end

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
