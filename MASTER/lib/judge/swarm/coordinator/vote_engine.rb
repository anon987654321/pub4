# frozen_string_literal: true

module Master
  module Judge
    module Swarm
      class Coordinator
        module VoteEngine
          private

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
              return :reject  if approved == false
            end
            text = value.to_s.downcase
            return :approve if text.match?(/\b(approv(e|ed)|looks good|no issues|lgtm)\b/)
            return :reject  if text.match?(/\b(reject|fail|error|violation|problem|insecure)\b/)
            :neutral
          end

          def summarize_outputs(workers)
            workers.map { |w| "#{w[:role]}: #{w[:output].value!.to_s.strip}" }.join("\n\n")
          end

          # Agent arbitrates when workers cannot reach consensus. Sends all outputs.
          def arbitrate(ok_workers, task_context)
            context = ok_workers.map { |w|
              "#{w[:role]} (confidence #{w[:confidence].round(2)}): #{w[:output].value!}"
            }.join("\n\n")
            prompt = "Workers could not reach consensus on: #{task_context}\n\nWorker outputs:\n#{context}\n\nPick the best recommendation and explain why."
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
