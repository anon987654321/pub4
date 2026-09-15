# frozen_string_literal: true

module Master
  module Core
    module Execution
      module States
        class Base
          attr_reader :goal, :container
          attr_accessor :current_focus

          def initialize(goal, container)
            @goal = goal
            @container = container
          end

          def call
            raise NotImplementedError, "State must implement #call"
          end

          protected

          def agent
            @container[:agent]
          end

          def world
            @container[:world]
          end

          def state_machine
            @container[:state_machine]
          end

          def record(event, data = {})
            state_machine.episode.record_event({
              type: event,
              data: data,
              timestamp: Time.now
            })
            @container[:bus]&.publish("exec:event", {
              type: event,
              data: data,
              presence: state_machine.presence.to_h
            })
          end

      def request_role(role, prompt_override = nil)
        # Use the ContextCompiler to build a lean prompt
        compiler = Master::Core::Execution::ContextCompiler.new(@container)
        context = compiler.compile(goal, state_machine, focus: @current_focus)
        
        # Construct the final lean prompt
        prompt = prompt_override || "Perform the role of #{role} for the current phase."
        full_prompt = {
          context: context,
          instruction: prompt
        }.to_json
        
        # Resolve model for this role via the RoleManager
        model_id = @container[:role_manager].model_for(role)
        
        # Use the agent to generate a response with the specific model
        # Assuming agent.generate(prompt, model: model_id)
        response = agent.generate(full_prompt, model: model_id)
        
        # Wrap response in an evidence chain if it creates an artifact
        chain = Master::Core::Execution::Evidence::Chain.new(
          role: role,
          action: :generate,
          output: response,
          goal: goal
        )
        state_machine.record_evidence(chain)
        response
      end

        end

        class Intent < Base
          def call
            record(:intent_processed)
            :discover
          end
        end

        class Discover < Base
          def call
            record(:discover_started)
            
            # Architect identifies the scope
            prompt = "Analyze the goal: '#{goal}'. Which files and contexts are required to solve this?"
            scope = request_role(:architect, prompt)
            
            # Observer gathers the data
            # In a real run, the agent would call tools here. For the skeleton, we record the intent to scan.
            record(:discover_completed, scope: scope)
            :analyze
          end
        end

        class Analyze < Base
          def call
            record(:analyze_started)
            
            prompt = "Based on the discovered scope, what is the root cause or the specific architectural change needed for: '#{goal}'?"
            analysis = request_role(:architect, prompt)
            
            record(:analyze_completed, analysis: analysis)
            :plan
          end
        end

        class Plan < Base
          def call
            record(:plan_started)
            
            prompt = "Create a step-by-step implementation plan for: '#{goal}'. Ensure every step is verifiable."
            plan = request_role(:architect, prompt)
            
            record(:plan_completed, plan: plan)
            :implement
          end
        end

        class Implement < Base
          def call
            record(:implement_started)
            
            prompt = "Execute the plan for: '#{goal}'. Provide the exact changes and justifications."
            implementation = request_role(:implementer, prompt)
            
            record(:implement_completed, implementation: implementation)
            :validate
          end
        end

        class Validate < Base
          def call
            record(:validate_started)
            
            prompt = "Verify the implementation of: '#{goal}'. Check for regressions, style violations, and correctness."
            verification = request_role(:validator, prompt)
            
            record(:validate_completed, verification: verification)
            :converge
          end
        end

        class Converge < Base
          def call
            if state_machine.all_verified?
              record(:converged, result: :success)
              :deliver
            else
              record(:converged, result: :failure, reason: "unverified_evidence")
              # Return to Analyze to refine the approach
              :analyze
            end
          end
        end

        class Deliver < Base
          def call
            record(:deliver_started)
            
            # Final summary and proof of convergence
            proof = state_machine.episode.summarize_proof
            record(:deliver_completed, proof: proof)
            :completed
          end
        end
      end
    end
  end
end
