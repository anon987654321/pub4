# frozen_string_literal: true

require "timeout"


module Master
  module Review
    module Swarm
      class Coordinator
        module VoteEngine
          private

          def tally_votes(artifacts)
            tally = { approved: 0, rejected: 0, neutral: 0 }
            artifacts.each_value do |v|
              case v.is_a?(Hash) ? v["approved"] : nil
              when true then tally[:approved] += 1
              when false then tally[:rejected] += 1
              else tally[:neutral] += 1
              end
            end
            tally
          end

          def derive_verdict(confidence, votes)
            if votes[:approved].positive? || votes[:rejected].positive?
              votes[:rejected] > votes[:approved] ? :rejected : :approved
            elsif confidence.zero? then :error
            elsif confidence >= 0.8 then :approved
            elsif confidence >= 0.5 then :mixed
            else :rejected
            end
          end

          def direct_fallback(task)
            @bus&.publish(:swarm_fallback_start, task: task[0..60])
            response = @agent.ask(task)
            SwarmResult.new(verdict: :approved, confidence: 0.5,
                            reasoning: response.to_s, artifacts: { fallback: response },
                            votes: { approved: 0, rejected: 0, neutral: 0 })
          rescue StandardError => e
            @bus&.publish(:swarm_fallback_failed, error: e.message)
            SwarmResult.new(verdict: :error, confidence: 0.0, reasoning: e.message, artifacts: {}, votes: { approved: 0, rejected: 0, neutral: 0 })
          end

          def conflict?(artifacts)
            signals = artifacts.filter_map { |_role, v| conflict_signal(v) }
            return false if signals.size < 2
            signals.include?(:approve) && signals.include?(:reject)
          end

          def resolve_conflict(artifacts)
            approve_weight = 0
            reject_weight = 0
            artifacts.each do |role, v|
              w = WORKER_WEIGHTS.fetch(role, 1)
              case conflict_signal(v)
              when :approve then approve_weight += w
              when :reject then reject_weight += w
              end
            end
            return :approved if approve_weight > reject_weight
            return :rejected if reject_weight > approve_weight
            :conflict
          end

          def conflict_signal(v)
            return v["approved"] ? :approve : :reject if v.is_a?(Hash) && v.key?("approved")

            text = v.to_s.downcase
            return :approve if text.match?(/\b(approv(e|ed)|looks good|no issues)\b/)

            :reject if text.match?(/\b(reject|fail|error|violation|problem)\b/)
          end

          # Confidence-weighted vote across ok_workers. Returns [consensus, dissent, arbitrated].
          # consensus is the recommendation text with >= CONSENSUS_THRESHOLD weighted agreement.
          # dissent is the array of worker entries that did not agree with the consensus.
          # arbitrated is true when the agent broke a tie; false otherwise.
          def vote(ok_workers, task_context)
            total_weight = weighted_confidence(ok_workers)

            # Group workers by their recommendation signal (:approve / :reject / :neutral).
            by_signal = ok_workers.group_by { |w| recommendation_signal(w[:output]) }
            best_signal, best_workers = by_signal.max_by { |_signal, workers| weighted_confidence(workers) }

            best_weight = best_workers ? weighted_confidence(best_workers) : 0.0
            agreement = total_weight.positive? ? best_weight / total_weight : 0.0

            build_vote_result(agreement, best_workers, ok_workers, task_context)
          end

          def weighted_confidence(workers)
            workers.sum { |w| WORKER_WEIGHTS.fetch(w[:role], 1) * w[:confidence] }
          end

          def build_vote_result(agreement, best_workers, ok_workers, task_context)
            return [arbitrate(ok_workers, task_context), [], true] if agreement < CONSENSUS_THRESHOLD

            [summarize_outputs(best_workers), ok_workers - best_workers, false]
          end

          def extract_confidence(result)
            return 0.0 unless result.ok?
            value = result.value!
            conf = value.is_a?(Hash) ? (value[:confidence] || value["confidence"]) : nil
            conf ? conf.to_f.clamp(0.0, 1.0) : 1.0
          end

          def recommendation_signal(result)
            return :neutral unless result.ok?
            value = result.value!
            if value.is_a?(Hash)
              approved = value["approved"] || value[:approved]
              return :approve if approved == true
              return :reject if approved == false
            end
            text = value.to_s.downcase
            return :approve if text.match?(/\b(approv(e|ed)|looks good|no issues|lgtm)\b/)
            return :reject if text.match?(/\b(reject|fail|error|violation|problem|insecure)\b/)
            :neutral
          end

          def summarize_outputs(workers)
            workers.map { |w| "#{w[:role]}: #{w[:output].value!.to_s.strip}" }.join("\n\n")
          end

          # Agent arbitrates when workers cannot reach consensus. Sends all outputs.
          def arbitrate(ok_workers, task_context)
            context = ok_workers.map do |w|
              "#{w[:role]} (confidence #{w[:confidence].round(2)}): #{w[:output].value!}"
            end.join("\n\n")
            prompt = "Workers failed to reach consensus on: #{task_context}\n\nWorker outputs:\n#{context}\n\nPick the best recommendation and explain why."
            @bus&.publish(:swarm_arbitration_start, task: task_context[0..60])
            @agent.ask(prompt)
          rescue StandardError => error
            @bus&.publish(:swarm_arbitration_failed, error: error.message)
            "(arbitration failed: #{error.message})"
          end
        end
      end
    end
  end
end

module Master
  module Review
    module Swarm
      class Coordinator
        SwarmResult = Struct.new(:verdict, :confidence, :reasoning, :artifacts, :votes, keyword_init: true) do
          def ok? = !%i[error insufficient_quorum].include?(verdict)
          def approved? = verdict == :approved
          def consensus?
            v = votes || { approved: 0, rejected: 0, neutral: 0 }
            v[:approved].to_i.positive? && v[:rejected].to_i.zero?
          end
        end

        WORKER_CLASSES = {
          analyst: Workers::Analyst,
          coder: Workers::Coder,
          reviewer: Workers::Reviewer,
          researcher: Workers::Researcher,
        }.freeze

        WORKER_WEIGHTS = { reviewer: 3, analyst: 2, researcher: 2, coder: 1 }.freeze

        WORKER_TIMEOUT = 30
        SHARED_DEADLINE = 60
        SYNTHESIS_TRUNCATE_LIMIT = 200
        MIN_QUORUM = 2
        CONSENSUS_THRESHOLD = 0.66

        include VoteEngine

        def initialize(agent:, event_bus: nil, parent_tools: nil)
          @agent = agent
          @bus = event_bus
          @parent_tools = Array(parent_tools)
          @workers = {}
        end

        def dispatch(role, task:, context_slice: {})
          worker = worker_for(role) or return Result.err("unknown role: #{role}")
          @bus&.publish(:swarm_dispatch, role:, task: task[0..60])
          worker.call(task:, context_slice:)
        end

        def analyse_and_review(file_path:, code:)
          fan_out([
            { role: :analyst, task: "identify all issues", context_slice: { file: file_path, code: } },
            { role: :reviewer, task: "security and correctness review", context_slice: { code: } },
          ]).and_then do |sr|
            analysis = sr.artifacts[:analyst]
            review = sr.artifacts[:reviewer]
            Result.ok({ analysis:, review:, approved: review.is_a?(Hash) && review["approved"] })
          end
        end

        def fan_out(tasks, timeout: WORKER_TIMEOUT)
          threads = tasks.map do |t|
            Thread.new do
              run_with_subagent_policy(t[:role]) do
                [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
              end
            rescue StandardError => e
              @bus&.publish("swarm:worker_error", role: t[:role], error: e.message)
              [t[:role], Result.err("worker error: #{e.message}", category: :infrastructure)]
            end
          end

          results = threads.map { |th| join_or_timeout(th, timeout) }.to_h
          sr = build_swarm_result(results)
          sr = direct_fallback(tasks.first&.dig(:task).to_s) if sr.verdict == :error

          @bus&.publish(:swarm_fan_out_done, roles: results.keys, verdict: sr.verdict,
                        synthesis: sr.reasoning[0..SYNTHESIS_TRUNCATE_LIMIT])
          Result.ok(sr)
        end

        def dispatch_parallel(role_tasks, deadline: SHARED_DEADLINE)
          finish_by = Process.clock_gettime(Process::CLOCK_MONOTONIC) + deadline
          threads = role_tasks.map { |t| spawn_role_thread(t, finish_by) }
          results = threads.map { |th| join_or_parallel_timeout(th, deadline) }.to_h

          sr = build_swarm_result(results)
          @bus&.publish(:swarm_dispatch_parallel_done, roles: results.keys, verdict: sr.verdict)
          Result.ok(sr)
        end

        def worker_roles = WORKER_CLASSES.keys

        # Spawn N workers in parallel, collect results within timeout, then run
        # confidence-weighted voting. Returns Result.ok with consensus/dissent/
        # arbitrated/workers keys. Partial quorum (>= MIN_QUORUM ok results)
        # proceeds; timed-out/errored slots carry Result.err payloads.
        def swarm_vote(tasks, timeout: WORKER_TIMEOUT)
          mutex = Mutex.new
          workers_out = []
          deadline = Time.now + timeout

          threads = tasks.map { |task_spec| spawn_vote_thread(task_spec, mutex, workers_out) }
          join_vote_threads(threads, deadline, timeout)

          ok_workers = workers_out.select { |w| w[:output].ok? }
          return insufficient_quorum_result(ok_workers, workers_out) if ok_workers.size < MIN_QUORUM

          consensus, dissent, arbitrated = vote(ok_workers, tasks.first&.dig(:task).to_s)
          @bus&.publish(:swarm_vote_done, arbitrated:, consensus: consensus.to_s[0..80])
          Result.ok({ consensus:, dissent:, arbitrated:, workers: workers_out })
        end

        private

        def spawn_role_thread(t, finish_by)
          Thread.new do
            run_with_subagent_policy(t[:role]) do
              remaining = [finish_by - Process.clock_gettime(Process::CLOCK_MONOTONIC), 1].max
              Timeout.timeout(remaining) do
                [t[:role], dispatch(t[:role], task: t[:task], context_slice: t.fetch(:context_slice, {}))]
              end
            end
          rescue Timeout::Error => _e
            [t[:role], Result.err("worker exceeded shared deadline", category: :timeout)]
          rescue StandardError => e
            @bus&.publish("swarm:worker_error", role: t[:role], error: e.message)
            [t[:role], Result.err("worker error: #{e.message}", category: :infrastructure)]
          end
        end

        def spawn_vote_thread(task_spec, mutex, workers_out)
          Thread.new do
            role = task_spec[:role]
            result = run_with_subagent_policy(role) do
              dispatch(role, task: task_spec[:task], context_slice: task_spec.fetch(:context_slice, {}))
            end
            confidence = extract_confidence(result)
            entry = { role:, output: result, confidence: }
            mutex.synchronize { workers_out << entry }
          rescue StandardError => error
            entry = { role: task_spec[:role],
                      output: Result.err("worker error: #{error.message}", category: :infrastructure),
                      confidence: 0.0 }
            mutex.synchronize { workers_out << entry }
          end
        end

        def join_vote_threads(threads, deadline, timeout)
          threads.each do |thread|
            remaining = [deadline - Time.now, 0].max
            unless thread.join(remaining)
              thread.kill rescue ThreadError
              @bus&.publish(:swarm_worker_timeout, timeout:)
            end
          end
        end

        def insufficient_quorum_result(ok_workers, workers_out)
          @bus&.publish(:swarm_vote_insufficient_quorum, count: ok_workers.size)
          Result.ok({ consensus: nil, dissent: workers_out, arbitrated: false,
                     workers: workers_out, verdict: :insufficient_quorum })
        end

        def join_or_timeout(th, timeout)
          return th.value if th.join(timeout)
          th.kill rescue ThreadError
          @bus&.publish(:swarm_worker_timeout, timeout:)
          [:timeout, Result.err("worker timed out after #{timeout}s", category: :timeout)]
        end

        def join_or_parallel_timeout(th, deadline)
          return th.value if th.join(deadline)
          th.kill rescue ThreadError
          @bus&.publish(:swarm_parallel_timeout, deadline:)
          [nil, Result.err("worker exceeded shared deadline", category: :timeout)]
        end

        def build_swarm_result(results)
          eligible = results.reject { |role, _| role == :timeout }
          successes = eligible.select { |_, r| r.is_a?(Master::Result) && r.ok? }
          artifacts = successes.transform_values(&:value!)

          total_weight = eligible.sum { |role, _| WORKER_WEIGHTS.fetch(role, 1) }
          success_weight = successes.sum { |role, _| WORKER_WEIGHTS.fetch(role, 1) }
          confidence = total_weight.zero? ? 0.0 : success_weight.to_f / total_weight

          lines = successes.map { |role, r| "### #{role}\n#{r.value!.to_s.strip}" }
          reasoning = lines.empty? ? "(no results)" : lines.join("\n\n")

          votes = tally_votes(artifacts)
          verdict = if eligible.empty? || successes.empty? then :error
                   elsif successes.size < MIN_QUORUM then :insufficient_quorum
                   elsif conflict?(artifacts) then resolve_conflict(artifacts)
                   else derive_verdict(confidence, votes)
                   end
          @bus&.publish("swarm:mixed_verdict", confidence:, reasoning: reasoning[0..120]) if verdict == :mixed
          SwarmResult.new(verdict:, confidence:, reasoning:, artifacts:, votes:)
        end

        def worker_for(role)
          sym = role.to_sym
          @workers.fetch(sym) do
            klass = WORKER_CLASSES[sym]
            return unless klass

            @workers[sym] = klass.new(agent: @agent, event_bus: @bus)
          end
        end

        def run_with_subagent_policy(role)
          ctx = Ground::Policy::Subagent.context_for_swarm_role(role, @parent_tools)
          Ground::SubagentContext.run(type: ctx[:type], allowed: ctx[:allowed]) { yield }
        end
      end
    end
  end
end
