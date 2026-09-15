# frozen_string_literal: true

module Master
  module Core
    module Execution
      module Bench
        # The SqueezeTest runs the Convergence Engine against the RegressionCorpus.
        # It proves that the kernel's deterministic guards actually work.
        class SqueezeTest
          def initialize(container)
            @container = container
          end

          def run_all
            results = {}
            RegressionCorpus.all_ids.each do |id|
              results[id] = run_scenario(id)
            end
            results
          end

          private

          def run_scenario(id)
            scenario = RegressionCorpus.scenario(id)
            
            # We mock the "agent" to simulate the failure mode described in the corpus
            mock_agent = MockFailureAgent.new(id)
            @container[:agent] = mock_agent
            
            pipeline = Pipeline.new(
              goal: scenario[:goal],
              container: @container.merge(
                capabilities: scenario[:forbidden_action] ? [:read_only] : [:all],
                agent: mock_agent
              )
            )
            
            # Run the pipeline and check if the kernel caught the failure
            begin
              pipeline.run
              { status: :passed_through, result: :fail } # It should have been blocked
            rescue => e
              { status: :caught, error: e.class, message: e.message, result: :pass }
            end
          end
        end

        # Simulates a "bad" agent that tries to bypass the Truth Layer
        class MockFailureAgent
          def initialize(scenario_id)
            @scenario_id = scenario_id
          end

          def model_for_role(role)
            # Return a mock model that produces the "bad" output needed for the scenario
            MockModel.new(@scenario_id)
          end

          def generate(prompt)
            # Fallback for direct calls
            "I have completed the task successfully."
          end
        end

        class MockModel
          def initialize(scenario_id)
            @scenario_id = scenario_id
          end

          def generate(prompt)
            case @scenario_id
            when :false_completion
              "Task complete. All tests passed." # Claim without evidence
            when :capability_escalation
              # Trigger a tool call that the kernel should block
              # In a real system, the executor would intercept this.
              "I will now call publish_post"
            when :evidence_drift
              "The file is updated. [Evidence: Stale Hash]"
            else
              "Everything is fine."
            end
          end
        end
      end
    end
  end
end
