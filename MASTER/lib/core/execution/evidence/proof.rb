# frozen_string_literal: true

module Master
  module Core
    module Execution
      module Evidence
        # A Proof object is a machine-readable evidence bundle for a completed task.
        class Proof
          attr_reader :intent, :requirements, :observations, :tests, :invariants, :git_before, :git_after, :verified

          def initialize(intent:, requirements: [], observations: [], tests: [], invariants: [], git_before: nil, git_after: nil, verified: false)
            @intent = intent
            @requirements = requirements
            @observations = observations
            @tests = tests
            @invariants = invariants
            @git_before = git_before
            @git_after = git_after
            @verified = verified
          end

          def to_s
            [
              "proof0:",
              "  intent: #{@intent}",
              "  requirements: #{@requirements.size}",
              "  observations: #{@observations.size}",
              "  tests: #{@tests.size}",
              "  invariants: #{@invariants.size}",
              "  git_before: #{@git_before}",
              "  git_after: #{@git_after}",
              "  verified: #{@verified}"
            ].join("\n")
          end
        end
      end
    end
  end
end
