# frozen_string_literal: true

module Master
  module Core
    module Execution
      # The ContextCompiler is the kernel's gatekeeper for LLM input.
      # It prevents context pollution by projecting only the smallest relevant
      # subset of the system state into the model's prompt.
      class ContextCompiler
        BUDGETS = {
          constitution: 2_500,
          task: 1_500,
          evidence: 6_000,
          files: 12_000,
          history: 1_500,
          tools: 2_500,
          reserve: 4_000,
        }.freeze

        def initialize(container)
          @container = container
        end

        # Compiles a lean, task-specific context projection.
        def compile(goal, state_machine, focus: nil)
          {
            task: compile_task(goal, state_machine),
            state: compile_state(state_machine),
            facts: compile_evidence(state_machine),
            files: compile_files(state_machine, focus),
            constraints: compile_constraints,
            output_contract: compile_contract(state_machine.current_state),
          }
        end

        private

        def compile_task(goal, sm)
          {
            intent: goal,
            episode_id: sm.episode.id,
            iteration: sm.history.size,
          }
        end

        def compile_state(sm)
          {
            phase: sm.current_state,
            presence: sm.presence.to_h[:phase],
            verified: sm.all_verified?,
          }
        end

        def compile_evidence(sm)
          # Project only verified facts and recent critical failures
          sm.episode.record.select { |e| e[:type] == :verification && e[:data][:ok] }
             .map { |e| e[:data][:fact] }
             .last(10)
        end

        def compile_files(sm, focus)
          # If focus is a specific symbol or file, prioritize it.
          # Otherwise, provide a list of files currently being attended to.
          return [focus] if focus.is_a?(String) && focus.start_with?("/")

          # Use the state machine's history to find recently read files
          sm.episode.record.select { |e| e[:type] == :observation }
             .map { |e| e[:data][:path] }
             .compact
             .uniq
             .last(5)
        end

        def compile_constraints
          # Static invariants from the constitution/soul
          [
            "preserve dmesg style",
            "no new dependencies",
            "Ruby only"
          ]
        end

        def compile_contract(phase)
          {
            phase: phase,
            required: phase == :implement ? [:patch, :tests] : [:analysis, :plan]
          }
        end
      end
    end
  end
end
