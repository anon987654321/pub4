# frozen_string_literal: true

module Master
  module CLI
    # Context is typed before it is compacted. State and telemetry are machine
    # memory, not conversation, so they do not enter the model by default.
    module ContextLayers
      LAYERS = %i[conversation task execution state telemetry].freeze
      MODEL_LAYERS = %i[conversation task execution].freeze

      module_function

      def normalize(value)
        layer = value.to_s.strip.to_sym
        LAYERS.include?(layer) ? layer : :conversation
      end

      def model_visible?(value)
        MODEL_LAYERS.include?(normalize(value))
      end

      def machine?(value)
        %i[state telemetry].include?(normalize(value))
      end
    end
  end
end
