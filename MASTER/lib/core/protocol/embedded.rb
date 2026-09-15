# frozen_string_literal: true

module Master
  module Core
    module Protocol
      # The MasterProtocol handles communication between the MASTER kernel
      # and embedded surfaces (like Brgen or Amber).
      # It defines the contract for intent submission and state observation.
      class Embedded
        def initialize(container)
          @container = container
        end

        # Submits a request from an embedded surface.
        # surface: where the request came from (e.g., "brgen_post_composer")
        # input: the natural language input
        # capabilities: the explicitly granted set of actions the surface allows
        def handle_intent(payload)
          surface = payload[:surface]
          input = payload[:input]
          capabilities = payload[:capabilities] || []

          # Create a structured intent for the kernel
          intent = {
            goal: input,
            surface: surface,
            capabilities: capabilities,
            timestamp: Time.now
          }

          # Kick off the execution pipeline
          # In a real async setup, this would return an episode_id immediately
          pipeline = Master::Core::Execution::Pipeline.new(
            goal: intent[:goal],
            container: @container.merge(surface: surface, capabilities: capabilities)
          )
          
          result = pipeline.run
          
          {
            episode_id: pipeline.instance_variable_get(:@state_machine).episode.id,
            status: :started,
            result: result
          }
        end

        # Retrieves the current semantic presence for a specific episode.
        def presence_for(episode_id)
          # Retrieve the latest presence state from the episode record
          episode = @container[:episode_store]&.find(episode_id)
          return { error: :not_found } unless episode
          
          episode.presence_state.to_h
        end

        # Allows the surface to cancel an ongoing operation.
        def cancel(episode_id)
          # Signal the event spine to stop the current execution
          @container[:bus]&.publish("exec:cancel", episode_id: episode_id)
          { status: :cancelled }
        end
      end
    end
  end
end
