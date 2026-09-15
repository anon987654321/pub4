# frozen_string_literal: true

module Master
  module UI
    module Render
      # The base renderer handles semantic event projection to a specific medium.
      class Base
        def initialize(profile:)
          @profile = profile
        end

        def render_event(event)
          raise NotImplementedError, "Renderer must implement #render_event"
        end

        def render_state(state)
          raise NotImplementedError, "Renderer must implement #render_state"
        end
      end

      class Terminal < Base
        def render_event(event)
          # project semantic event to ANSI terminal output
          # e.g., { type: "test.passed" } -> "test0: 87 passed\n"
          type = event[:type]
          data = event[:data]
          
          case type
          when "exec:state" then "state0: #{data[:state]}"
          when "test.passed" then "test0: #{data[:count]} passed"
          else "[#{type}] #{data}"
          end
        end

        def render_state(state)
          # renders the PresenceState as a terminal instrument
          "presence0: #{state.phase} (activity: #{state.activity})"
        end
      end
    end
  end
end
