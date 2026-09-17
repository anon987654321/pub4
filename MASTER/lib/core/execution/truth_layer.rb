# frozen_string_literal: true

require "digest"

module Master::Core::Execution
  # TruthLayer — the deterministic filter between raw observation and known truth.
  #
  # The Truth Layer accepts no claim as "True" until a deterministic
  # instrument verifies it.
  # Flow: Observation -> Verification -> Truth State
  class TruthLayer
    attr_reader :truth_state

    def initialize
      @truth_state = {} # { fact_id => { value: val, verified: bool, evidence: chain } }
    end

    # Processes a new observation.
    def process(observation, evidence_chain = nil)
      return Master::Result.err("no evidence provided", category: :validation) unless evidence_chain

      # Verification is the gate.
      verification = verify(observation, evidence_chain)

      if verification.ok?
        # The observation is promoted to Truth.
        fact_id = generate_fact_id(observation)
        @truth_state[fact_id] = {
          value: observation,
          verified: true,
          evidence: evidence_chain,
          timestamp: Time.now,
        }
        Master::Result.ok(fact_id)
      else
        Master::Result.err("observation failed verification", category: :validation)
      end
    end

    # Checks if a specific fact is currently known to be true.
    def true?(fact_id)
      @truth_state.key?(fact_id) && @truth_state[fact_id][:verified]
    end

    private

    def verify(observation, chain)
      # Integration with the state machine's verifier
      # For the skeleton, we trust the chain's internal verified state
      chain.verified? ? Master::Result.ok(true) : Master::Result.err("evidence not verified")
    end

    def generate_fact_id(observation)
      # Deterministic ID based on the content of the observation
      Digest::SHA256.hexdigest(observation.to_s)[0, 12]
    end
  end
end
