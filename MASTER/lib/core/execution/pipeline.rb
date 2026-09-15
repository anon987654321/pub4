# frozen_string_literal: true

require_relative "state_machine"
require_relative "voice/conversation"
require_relative "roles"
require_relative "role_manager"
require_relative "../domain/engine"

require_relative "../domain/verifier"

module Master
  module Core
    module Execution
      class Pipeline
        def initialize(goal:, container:)
          @goal = goal
          @container = container
          @state_machine = StateMachine.new(goal: goal, container: container)
          @container[:state_machine] = @state_machine
          @voice = Voice::Conversation.new(container)
          @container[:voice] = @voice
          
          # Role Management for Architect/Implementer/Validator split
          @role_manager = RoleManager.new(
            router: container[:model_router], 
            container: container
          )
          @container[:role_manager] = @role_manager

          # Domain Expertise Setup
          @domain_engine = Domain::Engine.new(container)

          @domain_verifier = Domain::Verifier.new(container)
          
          # If we are running in an embedded context, set up the capability contract
          if @container[:capabilities]
            @contract = Protocol::CapabilityContract.new(@container[:capabilities])
          end
        end

        def run
          # Detect and load domain expertise before starting
          domains = @domain_engine.detect_and_load(@container[:root])
          @container[:active_domains] = domains
          
          until @state_machine.completed?
            current_state = @state_machine.current_state
            
            # Publish event to the Event Spine
            @container[:bus]&.publish("exec:state", state: current_state, goal: @goal)
            
            # Trigger semantic voice responses
            voice_response = @voice.semantic_response(current_state)
            @container[:bus]&.publish("voice:speak", text: voice_response) if voice_response
            
            next_state = @state_machine.run_current_state
            
            if next_state == :completed
              # Truth Check + Domain Check
              simulation = @state_machine.verify_completion(:complete)
              domain_results = @domain_verifier.verify(@container[:root], domains)
              
              if simulation == :simulation_detected || domain_results[:failed].any?
                @container[:bus]&.publish("exec:domain_failure", failures: domain_results[:failed])
                @state_machine.transition_to(:validate)
                next
              end
            
              @state_machine.transition_to(:deliver)
              @state_sMachine.run_current_state
              break
            end
            
            @state_machine.transition_to(next_state)
          end
          
          Master::Result.ok(proof: @state_machine.all_verified?)
        end

        def can_execute?(action)
          return true unless @contract
          @contract.permitted?(action)
        end
      end
    end
  end
end

