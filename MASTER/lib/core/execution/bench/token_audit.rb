# frozen_string_literal: true

module Master
  module Core
    module Execution
      module Bench
        # The TokenAudit measures the efficiency of the ContextCompiler.
        # It compares the "lean" projection against a "naive" full-context dump.
        class TokenAudit
          def initialize(container)
            @container = container
            @compiler = ContextCompiler.new(container)
          end

          # Measures the token savings for a given goal and state.
          def audit(goal, state_machine)
            lean_context = @compiler.compile(goal, state_machine)
            naive_context = compile_naive(goal, state_machine)
            
            lean_size = estimate_tokens(lean_context)
            naive_size = estimate_tokens(naive_context)
            
            {
              lean_tokens: lean_size,
              naive_tokens: naive_size,
              savings: naive_size - lean_size,
              efficiency: (1.0 - (lean_size.to_f / naive_size)).round(4),
              ratio: (naive_size.to_f / lean_size).round(2)
            }
          end

          private

          def compile_naive(goal, sm)
            # Simulates the "naive" approach: dump everything
            {
              goal: goal,
              full_history: sm.episode.record,
              full_evidence: sm.evidence_ledger,
              all_files: sm.episode.record.select { |e| e[:type] == :observation }.map { |e| e[:data] },
              full_constitution: "Full constitutional text..." # Simulated
            }
          end

          def estimate_tokens(data)
            # Rough estimation based on string length / 4
            # In a real system, this would call a tokenizer like Tiktoken
            data.to_json.length / 4
          end
        end
      end
    end
  end
end
