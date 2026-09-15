# frozen_string_literal: true

module Master
  module Core
    module Execution
      # The Replay system allows the user to "watch" a past episode.
      # It re-projects the Event Spine and Presence state without LLM calls.
      class Replay
        def initialize(container)
          @container = container
        end

        # Re-projects an episode's history to the current Presence layer.
        def play(episode_id)
          episode = @container[:episode_store]&.find(episode_id)
          return { error: :not_found } unless episode
          
          # Project each event in the record to the Event Spine
          episode.record.each do |event|
            # Re-publish the event to trigger the same visual/voice reactions
            @container[:bus]&.publish(event[:type], event[:data])
            
            # Update the presence based on the captured state
            if event[:presence]
              @container[:bus]&.publish("presence:update", event[:presence])
            end
          end
          
          { status: :completed, episode: episode_id }
        end
      end
    end
  end
end
