# frozen_string_literal: true

module Master
  module Core
    module Discovery
      # FalsificationLoop — the research substrate for turning hypotheses into reality.
      # It follows the loop: Imagined (Hypothesis) -> Simulated (Model) -> Observed (Evidence).
      class FalsificationLoop
        attr_reader :hypothesis_store, :bus

        def initialize(event_bus: nil)
          @bus = event_bus
          @hypothesis_store = {} # Maps hypothesis_id to its current stage: :imagined, :simulated, :observed
        end

        # Registers a new architectural hypothesis.
        def imagine(id, description, expected_outcome:)
          @hypothesis_store[id] = {
            stage: :imagined,
            description: description,
            expected_outcome: expected_outcome,
            timestamp: Time.now
          }
          @bus&.publish("discovery:hypothesized", id: id, description: description)
          { id: id, stage: :imagined }
        end

        # Attempts to simulate the hypothesis using a model or a test case.
        def simulate(id, simulation_result:)
          return unless @hypothesis_store.key?(id)
          
          h = @hypothesis_store[id]
          h[:stage] = :simulated
          h[:simulation_result] = simulation_result
          
          if simulation_result[:success]
            @bus&.publish("discovery:simulated", id: id, outcome: :positive)
          else
            @bus&.publish("discovery:falsified", id: id, outcome: :negative, reason: simulation_result[:reason])
          end
          
          { id: id, stage: :simulated, outcome: simulation_result[:success] ? :positive : :negative }
        end

        # Verifies the simulated outcome against real-world evidence (Observed).
        def observe(id, evidence:)
          return unless @hypothesis_store.key?(id)
          
          h = @hypothesis_store[id]
          return if h[:stage] != :simulated # Must be simulated before it can be observed
          
          h[:stage] = :observed
          h[:evidence] = evidence
          
          if evidence[:verified]
            @bus&.publish("discovery:verified", id: id, evidence: evidence)
          else
            @bus&.publish("discovery:falsified", id: id, outcome: :negative, reason: "Observation contradicts simulation")
          end
          
          { id: id, stage: :observed, verified: evidence[:verified] }
        end

        def status(id)
          @hypothesis_store[id]
        end
      end
    end
  end
end
