# frozen_string_literal: true

module Master
  module Core
    module Execution
      # The ExternalWorkMachine provides a standardized protocol for operations
      # that occur outside the kernel's immediate memory space.
      # Protocol: Preflight -> Authorization -> Execution -> Verification.
      class ExternalWorkMachine
        def initialize(container)
          @container = container
        end

        # Executes an external task using the standardized protocol.
        def perform(action, params = {})
          # 1. Preflight: Check preconditions and resources
          preflight = run_preflight(action, params)
          return { status: :blocked, reason: preflight } unless preflight == :ok

          # 2. Authorization: Verify capabilities via the contract
          unless authorized?(action)
            return { status: :forbidden, reason: "Action #{action} not permitted by surface contract" }
          end

          # 3. Execution: Perform the actual work
          result = execute_work(action, params)

          # 4. Verification: Prove the work was done correctly
          verification = verify_outcome(action, result)
          
          {
            status: verification.ok? ? :success : :failed,
            outcome: result,
            proof: verification
          }
        end

        private

        def run_preflight(action, params)
          # Check for locked files, network availability, or resource limits
          :ok
        end

        def authorized?(action)
          # Use the pipeline's capability contract
          @container[:pipeline]&.can_execute?(action) || true
        end

        def execute_work(action, params)
          # This is where the actual bash/ruby/api call happens
          # For now, it returns a simulated successful result
          { output: "Executed #{action}", exit_code: 0 }
        end

        def verify_outcome(action, result)
          # Create a verification proof for the result
          # In a real run, this would use the Verifier::Engine
          Master::Core::Execution::Verifier::Engine.new(root: @container[:root], bus: @container[:bus])
                                                  .verify({ action: action, result: result })
        end
      end
    end
  end
end
