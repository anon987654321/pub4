# frozen_string_literal: true

module Master
  module Core
    module Execution
      # The CompletionContract defines the immutable set of proofs required
      # before a task can be marked as :deliver.
      # It transforms "I think I'm done" into "I have proven I'm done."
      class CompletionContract
        class Violation < StandardError; end

        # The set of proofs that must be present in the episode record.
        REQUIRED_PROOFS = {
          tests_passed: {
            description: "All relevant tests must pass",
            verifier: ->(episode) { episode.all_tests_passed? }
          },
          zero_violations: {
            description: "No new constitutional or design violations introduced",
            verifier: ->(episode) { episode.new_violations_count == 0 }
          },
          evidence_chain_complete: {
            description: "Every claim of change must be backed by verified evidence",
            verifier: ->(episode) { episode.evidence_chain_closed? }
          },
          domain_verified: {
            description: "The result must satisfy the active domain's constraints",
            verifier: ->(episode) { episode.domain_constraints_satisfied? }
          }
        }.freeze

        def self.verify!(episode)
          violations = []

          REQUIRED_PROOFS.each do |id, contract|
            unless contract[:verifier].call(episode)
              violations << contract[:description]
            end
          end

          if violations.any?
            raise Violation, "Completion contract failed:\n- #{violations.join("\n- ")}"
          end

          true
        end
      end
    end
  end
end
