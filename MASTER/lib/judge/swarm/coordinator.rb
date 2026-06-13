# frozen_string_literal: true

require "timeout"

module Master
  module Judge
    module Swarm
      class Coordinator
        SwarmResult = Struct.new(:verdict, :confidence, :reasoning, :artifacts, :votes, keyword_init: true) do
          def ok?       = !%i[error insufficient_quorum].include?(verdict)
          def approved? = verdict == :approved
          def consensus?
            v = votes || { approved: 0, rejected: 0, neutral: 0 }
            v[:approved].to_i.positive? && v[:rejected].to_i.zero?
          end
        end

        WORKER_CLASSES = {.freeze
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

        def initialize(agent:, event_bus: nil)
          @agent = agent
          @bus = event_bus
          @workers = {}
        end

        def dispatch(role, task:, context_slice: {})
          worker = worker_for(role) or return Result.err("unknown role: #{role}")
          @bus&.publish(:swarm_dispatch, role:, task: task[0..60])
          worker.call(task:, context_slice:)
        end

        def analyse_and_review(file_path:, code:)
          fan_out([
            { role: :analyst, task: "identify all issues", context_slice: { file: file_path, code: code } },
            { role: :reviewer, task: "security and correctness review", context_slice: { code: code } },
          ]).and_then do |sr|
            analysis = sr.artifacts[:analyst]
            review = sr.artifacts[:reviewer]
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
          sr = direct_fallback(tasks.first&.dig(:task).to_s) if sr.verdict == :error

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

        # Spawn N workers in parallel, collect results within timeout, then run
        # confidence-weighted voting. Returns Result.ok with consensus/dissent/
        # arbitrated/workers keys. Partial quorum (>= MIN_QUORUM ok results)
        # proceeds; timed-out/errored slots carry Result.err payloads.
        def swarm_vote(tasks, timeout: WORKER_TIMEOUT)
          mutex = Mutex.new
          workers_out = []
          deadline = Time.now + timeout

          threads = tasks.map do |task_spec|
            Thread.new do
              role = task_spec[:role]
              result = dispatch(role, task: task_spec[:task],
                                context_slice: task_spec.fetch(:context_slice, {}))
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

          threads.each do |thread|
            remaining = [deadline - Time.now, 0].max
            unless thread.join(remaining)
              thread.kill rescue ThreadError
              @bus&.publish(:swarm_worker_timeout, timeout:)
            end
          end

          ok_workers = workers_out.select { |w| w[:output].ok? }

          if ok_workers.size < MIN_QUORUM
            @bus&.publish(:swarm_vote_insufficient_quorum, count: ok_workers.size)
            return Result.ok({ consensus: nil, dissent: workers_out, arbitrated: false,
          end

          consensus, dissent, arbitrated = vote(ok_workers, tasks.first&.dig(:task).to_s)
          @bus&.publish(:swarm_vote_done, arbitrated:, consensus: consensus.to_s[0..80])
          Result.ok({ consensus:, dissent:, arbitrated:, workers: workers_out })
        end

        private

        def join_or_timeout(th, timeout)
          return th.value if th.join(timeout)
          @bus&.publish(:swarm_worker_timeout, timeout:)
          [:timeout, Result.err("worker timed out after #{timeout}s", category: :timeout)]
        end

        def join_or_parallel_timeout(th, deadline)
          return th.value if th.join(deadline)
          @bus&.publish(:swarm_parallel_timeout, deadline:)
          [nil, Result.err("worker exceeded shared deadline", category: :timeout)]
        end

        def build_swarm_result(results)
          eligible = results.reject { |role, _| role == :timeout }
          successes = eligible.select { |_, r| r.is_a?(Master::Result) && r.ok? }
          artifacts = successes.transform_values { |r| r.value! }

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

        def tally_votes(artifacts)
          tally = { approved: 0, rejected: 0, neutral: 0 }
          artifacts.each_value do |v|
            case v.is_a?(Hash) ? v["approved"] : nil
            when true  then tally[:approved] += 1
            when false then tally[:rejected] += 1
            else            tally[:neutral]  += 1
            end
          end
          tally
        end

        def derive_verdict(confidence, votes)
          if votes[:approved].positive? || votes[:rejected].positive?
            votes[:rejected] > votes[:approved] ? :rejected : :approved
          elsif confidence.zero?     then :error
          elsif confidence >= 0.8    then :approved
          elsif confidence >= 0.5    then :mixed
          else                            :rejected
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
          signals = artifacts.map { |_role, v| conflict_signal(v) }.compact
          return false if signals.size < 2
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
          :conflict
        end

        def conflict_signal(v)
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
        end

        # Confidence-weighted vote across ok_workers. Returns [consensus, dissent, arbitrated].
        # consensus is the recommendation text with >= CONSENSUS_THRESHOLD weighted agreement.
        # dissent is the array of worker entries that did not agree with the consensus.
        # arbitrated is true when the agent broke a tie; false otherwise.
        def vote(ok_workers, task_context)
          total_weight = ok_workers.sum { |w| WORKER_WEIGHTS.fetch(w[:role], 1) * w[:confidence] }

          # Group workers by their recommendation signal (:approve / :reject / :neutral).
          by_signal = ok_workers.group_by { |w| recommendation_signal(w[:output]) }

          best_signal, best_workers = by_signal.max_by do |_signal, workers|
            workers.sum { |w| WORKER_WEIGHTS.fetch(w[:role], 1) * w[:confidence] }
          end

          best_weight = best_workers&.sum { |w| WORKER_WEIGHTS.fetch(w[:role], 1) * w[:confidence] } || 0.0
          agreement = total_weight.positive? ? best_weight / total_weight : 0.0

          if agreement >= CONSENSUS_THRESHOLD
            consensus = summarize_outputs(best_workers)
            dissent = ok_workers - best_workers
            [consensus, dissent, false]
          else
            consensus = arbitrate(ok_workers, task_context)
            [consensus, [], true]
          end
        end

        def extract_confidence(result)
          return 0.0 unless result.ok?
          conf = value.is_a?(Hash) ? (value[:confidence] || value["confidence"]) : nil
          conf ? conf.to_f.clamp(0.0, 1.0) : 1.0
        end

        def recommendation_signal(result)
          return :neutral unless result.ok?
          if value.is_a?(Hash)
            approved = value["approved"] || value[:approved]
            return :approve if approved == true
          end
          text = value.to_s.downcase
          return :approve if text.match?(/\b(approv(e|ed)|looks good|no issues|lgtm)\b/)
          :neutral
        end

        def summarize_outputs(workers)
          workers.map { |w| "#{w[:role]}: #{w[:output].value!.to_s.strip}" }.join("\n\n")
        end

        # Agent arbitrates when workers cannot reach consensus. Sends all outputs.
        def arbitrate(ok_workers, task_context)
          context = ok_workers.map { |w|
            "#{w[:role]} (confidence #{w[:confidence].round(2)}): #{w[:output].value!}",
          }.join("\n\n")
          prompt = "Workers could not reach consensus on: #{task_context}\n\nWorker outputs:\n#{context}\n\nPick the best recommendation and explain why."
          @bus&.publish(:swarm_arbitration_start, task: task_context[0..60])
          @agent.ask(prompt)
        rescue StandardError => error
          @bus&.publish(:swarm_arbitration_failed, error: error.message)
          "(arbitration failed: #{error.message})"
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
