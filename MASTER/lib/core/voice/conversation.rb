# frozen_string_literal: true

module Master
  module Core
    module Voice
      # The Conversation handler manages the high-level interaction loop.
      # It ensures MASTER sounds natural, avoids machine-verbosity,
      # and handles barge-in/interruptions.
      class Conversation
        attr_reader :state, :container

        def initialize(container)
          @container = container
          @state = :idle # :idle, :listening, :thinking, :speaking
        end

        # Determines the most natural spoken response based on the event.
        def semantic_response(event_type, data = {})
          case event_type
          when :discover_started then "Checking."
          when :discover_completed then "Found it."
          when :implement_started then "On it."
          when :validate_started then "Verifying."
          when :converged then data[:result] == :success ? "Done." : "Something's off. Retrying."
          when :deliver_completed then "Here you go."
          else
            nil # Let the LLM handle complex responses
          end
        end

        def transition_to(new_state)
          @state = new_state
          @container[:bus]&.publish("voice:state", state: @state)
        end

        # Handles user interruption (barge-in)
        def handle_interruption
          transition_to(:listening)
          # Immediately signal the TTS engine to kill current playback
          @container[:bus]&.publish("voice:interrupt", action: :cancel_playback)
        end

        def process_input(transcript)
          transition_to(:thinking)
          # Route transcript to MASTER's intent processor
          @container[:bus]&.publish("intent:input", text: transcript)
        end
      end
    end
  end
end
