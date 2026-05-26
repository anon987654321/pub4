# frozen_string_literal: true

require "timeout"

module Master
  module Judge
  module Swarm
    class Coordinator
      SwarmResult = Struct.new(:verdict, :confidence, :reasoning, :artifacts, keyword_init: true) do
        def ok?      = !%i[error insufficient_quorum].include?(verdict)
        def approved? = verdict == :approved
      end

      WORKER_CLASSES = {
        analyst:    Workers::Analyst,
        coder:      Workers::Coder,
        reviewer:   Workers::Reviewer,
        researcher: Workers::Researcher
      }.freeze

      # Higher weight = more authority in verdict calculation.
      WORKER_WEIGHTS = { reviewer: 3, analyst: 2, researcher: 2, coder: 1 }.freeze

      WORKER_TIMEOUT = 30
      SHARED_DEADLINE = 60
      SYNTHESIS_TRUNCATE_LIMIT = 200
      MIN_QUORUM = 2

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
        @workers = {}
      end

      def dispatch(role, task:, context_slice: {})
        worker = worker_for(role) or return Result.err("unknown role: #{role}")
        @bus&.publish(:swarm_dispatch, role:, task: task[0..60])
        worker.call(task:, context_slice:)
      end

      def analyse_and_review(file_path:, code:)
        fan_out([
          { role: :analyst,  task: "identify all issues",          context_slice: { file: file_path, code: code } },
          { role: :reviewer, task: "security and correctness review", context_slice: { code: code } }
        ]).and_then do |sr|
          analysis = sr.artifacts[:analyst]
          review   = sr.artifacts[:reviewer]
          Result.ok({ analysis:, review:, approved: review.is_a?(Hash) && review["approved"] })
        end
      end

      def fan_out(tasks, timeout: WORKER_TIMEOUT)
        threads = tasks.map do |t|
          Thread.new do
            [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
          rescue StandardError => e
            @bus&.publish("swarm:worker_error", role: t[:role], error: e.message)
            [t[:role], Result.err("worker error: #{e.message}", category: :infrastructure)]
          end
        end

        results = threads.map { |th| join_or_timeout(th, timeout) }.to_h

        sr = build_swarm_result(results)
        @bus&.publish(:swarm_fan_out_done, roles: results.keys, verdict: sr.verdict,
                      synthesis: sr.reasoning[0..SYNTHESIS_TRUNCATE_LIMIT])
        Result.ok(sr)
      end

      def dispatch_parallel(role_tasks, deadline: SHARED_DEADLINE)
        finish_by = Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline

        threads = role_tasks.map do |t|
          Thread.new do
            remaining = [finish_by - Process.clock_gettime(Process::CLOCK_MONOTONIC), 1].max
            Timeout.timeout(remaining) do
              [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
            end
          rescue Timeout::Error => _e
            [t[:role], Result.err("worker exceeded shared deadline", category: :timeout)]
          rescue StandardError => e
            @bus&.publish("swarm:worker_error", role: t[:role], error: e.message)
            [t[:role], Result.err("worker error: #{e.message}", category: :infrastructure)]
          end
        end

        results = threads.map { |th| join_or_parallel_timeout(th, deadline) }.to_h

        sr = build_swarm_result(results)
        @bus&.publish(:swarm_dispatch_parallel_done, roles: results.keys, verdict: sr.verdict)
        Result.ok(sr)
      end

      def worker_roles = WORKER_CLASSES.keys

      private

      def join_or_timeout(th, timeout)
        return th.value if th.join(timeout)
        begin; th.kill; rescue ThreadError; nil; end
        @bus&.publish(:swarm_worker_timeout, timeout:)
        [:timeout, Result.err("worker timed out after #{timeout}s", category: :timeout)]
      end

      def join_or_parallel_timeout(th, deadline)
        return th.value if th.join(deadline)
        begin; th.kill; rescue ThreadError; nil; end
        @bus&.publish(:swarm_parallel_timeout, deadline:)
        [nil, Result.err("worker exceeded shared deadline", category: :timeout)]
      end

      def build_swarm_result(results)
        eligible  = results.reject { |role, _| role == :timeout }
        successes = eligible.select { |_, r| r.is_a?(Master::Result) && r.ok? }
        artifacts = successes.transform_values { |r| r.value! }

        total_weight   = eligible.sum { |role, _| WORKER_WEIGHTS.fetch(role, 1) }
        success_weight = successes.sum { |role, _| WORKER_WEIGHTS.fetch(role, 1) }
        confidence = total_weight.zero? ? 0.0 : success_weight.to_f / total_weight

        lines = successes.map { |role, r| "### #{role}\n#{r.value!.to_s.strip}" }
        reasoning = lines.empty? ? "(no results)" : lines.join("\n\n")

        conflict = conflict?(artifacts)
        verdict = if eligible.empty? || successes.empty? then :error
                 elsif successes.size < MIN_QUORUM then :insufficient_quorum
                 elsif conflict then :conflict
                 elsif confidence >= 0.8 then :approved
                 elsif confidence >= 0.5 then :mixed
                 else :rejected
                 end
        @bus&.publish("swarm:mixed_verdict", confidence:, reasoning: reasoning[0..120]) if verdict == :mixed
        SwarmResult.new(verdict:, confidence:, reasoning:, artifacts:)
      end

      def conflict?(artifacts)
        signals = artifacts.map do |_role, v|
          if v.is_a?(Hash) && v.key?("approved")
            v["approved"] ? :approve : :reject
          else
            text = v.to_s.downcase
            if text.match?(/\b(approv(e|ed)|looks good|no issues)\b/)
              :approve
            elsif text.match?(/\b(reject|fail|error|violation|problem)\b/)
              :reject
            end
          end
        end.compact
        return false if signals.size < 2
        signals.include?(:approve) && signals.include?(:reject)
      end

      def worker_for(role)
        sym = role.to_sym
        @workers.fetch(sym) do
          klass = WORKER_CLASSES[sym]
          return unless klass

          @workers[sym] = klass.new(agent: @agent, event_bus: @bus)
        end
      end
    end
  end
  end
end
