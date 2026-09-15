# frozen_string_literal: true

module Master
  module Core
    module Execution
      # The state machine governing the lifecycle of a task.
      # Transitions: Intent -> Discover -> Analyze -> Plan -> Implement -> Validate -> Converge -> Deliver
      class StateMachine
        STATES = %i[intent discover analyze plan implement validate converge deliver].freeze

        attr_reader :current_state, :presence, :history, :episode, :trace

        def initialize(goal:, container:)
          @goal = goal
          @container = container
          @current_state = :intent
          @history = []
          @evidence_ledger = []
          @verifier = Verifier::Engine.new(root: container[:root], bus: container[:bus])
          @presence = Presence::State.new(phase: :idle)
          @episode = Episode::Record.new(id: SecureRandom.hex(4), intent: goal)
          @trace = StructuralTrace.new
        end

        def transition_to(next_state)
          unless STATES.include?(next_state)
            raise ArgumentError, "invalid state: #{next_state}"
          end
          
          # Capture current state as an observation before transitioning
          record_system_snapshot
          
          @history << { state: @current_state, timestamp: Time.now }
          @current_state = next_state
          
          # Update presence state
          @presence = @presence.update(phase: next_state)
          
          # Record transition in the episode
          @episode.record_event({ type: "state_transition", from: @history.last[:state], to: next_state, timestamp: Time.now })
          
          # Publish event to the Event Spine
          # Now we publish a semantic event that can be rendered by the UI
          @container[:bus]&.publish("exec:event", {
            type: "state_transition",
            phase: next_state,
            presence: @presence.to_h,
            goal: @goal
          })
        end

        def record_system_snapshot
          snapshot = Observer::SystemState.new(root: @container[:root])
          @evidence_ledger << snapshot
          @episode.record_observation(snapshot)
        end

        def record_evidence(chain)
          @evidence_ledger << chain
          # Immediately attempt to verify the new evidence
          verification = @verifier.verify(chain)
          chain.verify(verification) if verification.ok?
          
          @episode.record_verification(verification) if verification.ok?

          # Link the evidence to the structural trace
          entry = @trace.record(
            role: chain.role,
            intent: @goal,
            effect: chain.action,
            observation: verification.message,
            evidence: chain
          )
          @episode.record_trace_entry(entry)
        end

        def completed?
          @current_state == :deliver
        end

        def run_current_state
          state_class = Master::Core::Execution::States.const_get(
            @current_state.to_s.capitalize
          )
          state_class.new(@goal, @container).call
        end

        def all_verified?
          # Only verify chains that are evidence; snapshots are observations
          chains = @evidence_ledger.select { |e| e.respond_to?(:verified?) }
          return false if chains.empty?
          chains.all? { |chain| chain.verified? }
        end
      end
    end
  end
end
