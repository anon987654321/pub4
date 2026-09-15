# frozen_string_literal: true

module Master
  module Core
    module Execution
      module Truth
        # The Truth Layer prevents the promotion of language into reality.
        # It manages the transition from Claim -> Evidence -> Truth.
        class Layer
          def initialize(verifier:, bus: nil)
            @verifier = verifier
            @bus = bus
          end

          # Promotes a claim to truth if evidence is verified.
          def verify_claim(claim, evidence)
            result = @verifier.verify(evidence)
            
            if result.ok? && result.value[:truth] == :verified
              @bus&.publish("truth:verified", claim: claim, evidence: evidence)
              return :verified
            end
            
            :unverified
          end

          # Detects "false completion" (anti-simulation)
          def detect_simulation(claim, evidence)
            if claim == :complete && !evidence.all?(&:verified?)
              @bus&.publish("truth:simulation", claim: claim, evidence: evidence)
              return :simulation_detected
            end
            
            :genuine
          end
        end
      end
    end
  end
end
