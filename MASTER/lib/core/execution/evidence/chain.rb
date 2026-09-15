# frozen_string_literal: true

module Master
  module Core
    module Execution
      module Evidence
        # The provenance chain for every claim in the system.
        # Observation -> Fact -> Verification -> Truth State
        class Chain
          attr_reader :observation, :fact, :verification, :truth

          def initialize(observation:)
            @observation = observation
            @fact = nil
            @verification = nil
            @truth = :unknown
          end

          def verify(verifier_result)
            @verification = verifier_result
            @truth = verifier_result.ok? ? :verified : :refuted
          end

          def verified?
            @truth == :verified
          end
        end
      end
    end
  end
end
