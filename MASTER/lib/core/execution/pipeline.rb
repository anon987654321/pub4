# frozen_string_literal: true

module Master
  module Core
    module Execution
      # Runs a goal through the state machine: intent to deliver, with the role
      # split, the completion contract and the truth layer placed in the
      # container for the states to reach.
      #
      # Nothing calls it yet. As first committed it required a voice
      # conversation, a domain engine and verifier and a capability contract
      # that were never built, so loading the file raised LoadError and the
      # runtime could not boot; those collaborators are absent here until they
      # exist, and a state that needs them will say so when it runs.
      class Pipeline
        def initialize(goal:, container:)
          @goal = goal
          @container = container
          @state_machine = StateMachine.new(goal:, container:)
          @contract = CompletionContract.new
          publish_collaborators
        end

        def run
          until @state_machine.completed?
            state = @state_machine.current_state
            @container[:bus]&.publish("exec:state", state:, goal: @goal)
            next_state = @state_machine.run_current_state
            next_state = completion_state if next_state == :completed
            @state_machine.transition_to(next_state)
          end

          Master::Result.ok(proof: @state_machine.all_verified?)
        end

        private

        def publish_collaborators
          @container[:state_machine] = @state_machine
          @container[:role_manager] = RoleManager.new(router: @container[:model_router], container: @container)
          @container[:completion_contract] = @contract
          @container[:truth_layer] = TruthLayer.new
          @container[:regression_corpus] = AdversarialRegressionCorpus.new
        end

        # Done is delivered only past the completion contract; otherwise the
        # work goes back to validation.
        def completion_state
          return :deliver if @contract.verify(@state_machine).ok?

          @container[:bus]&.publish("exec:contract_refused", goal: @goal)
          :validate
        end
      end
    end
  end
end
