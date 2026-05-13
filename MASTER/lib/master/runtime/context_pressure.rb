# frozen_string_literal: true

module Master
  module Runtime
    class ContextPressure
      attr_reader :load, :switches

      OVERLOAD_THRESHOLD = 7.5

      def initialize
        @load = 0.0
        @switches = 0
        @recent = []
      end

      def push(concept, weight: 1.0)
        @recent << { concept: concept, weight: weight.to_f }
        @load += weight.to_f
        self
      end

      def overloaded?
        @load >= OVERLOAD_THRESHOLD
      end

      def reset!(keep_recent: 3)
        @recent = @recent.last(keep_recent)
        @load = @recent.sum { |entry| entry[:weight] }
        @switches = 0
        self
      end

      def update_flow(context_switches: 0)
        @switches += context_switches.to_i
        self
      end

      def flow_state
        return :overloaded if overloaded?
        return :strained if @load >= 4.0

        :optimal
      end

      def state
        {
          load: @load.round(3),
          switches: @switches,
          flow_state: flow_state,
          overload_risk: (@load / OVERLOAD_THRESHOLD).round(3),
          complexity: (@recent.size + @switches)
        }
      end
    end
  end
end
