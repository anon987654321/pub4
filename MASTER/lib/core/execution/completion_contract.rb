# frozen_string_literal: true

module Master::Core::Execution
  # CompletionContract — the deterministic definition of "Done".
  #
  # A task is not completed when the model says so, but when the contract
  # is satisfied. The contract consists of a set of required evidence
  # and a zero-tolerance policy for unresolved violations.
  class CompletionContract
    attr_reader :requirements

    def initialize(requirements: default_requirements)
      @requirements = requirements
    end

    # Validates if the current state of the pipeline satisfies the contract.
    # Returns a Result: ok if satisfied, err with missing requirements if not.
    def verify(state_machine)
      missing = requirements.select { |req| !satisfied?(req, state_machine) }
      
      if missing.empty?
        Master::Result.ok(true)
      else
        Master::Result.err("completion contract not satisfied: missing #{missing.join(', ')}", category: :verification)
      end
    end

    private

    def satisfied?(requirement, state_machine)
      case requirement
      when :tests_passed
        # Check if the evidence ledger contains a verified test_pass
        state_machine.all_verified? && 
          state_machine.instance_variable_get(:@evidence_ledger).any? { |e| e.respond_to?(:kind) && e.kind == :test_pass }
      when :scan_clean
        state_machine.instance_variable_get(:@evidence_ledger).any? { |e| e.respond_to?(:kind) && e.kind == :scan_clean }
      when :no_violations
        # Ensure no high-risk violations were recorded in the episode
        !state_machine.episode.events.any? { |e| e[:type] == "violation" && e[:severity] == :high }
      else
        false
      end
    end

    def default_requirements
      [:tests_passed, :scan_clean, :no_violations].freeze
    end
  end
end
