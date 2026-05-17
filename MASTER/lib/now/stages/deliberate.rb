# frozen_string_literal: true

module Master
  module Now
  module Stages
    # Deliberate — enumerate N approaches before acting; prevents first-solution fixation.
    class Deliberate
      MIN_OPTIONS   = 4
      CODING_TYPES  = %i[coding refactor architecture infrastructure].freeze

      def initialize(agent:, config:)
        @agent  = agent
        @config = config
      end

      def call(ctx)
        return Result.ok(ctx) unless applicable?(ctx)

        msg    = ctx[:message].to_s
        Result.ok(ctx.merge(message: wrap(msg)))
      end

      private

      def applicable?(ctx)
        ctx[:intent] == :llm &&
          CODING_TYPES.include?(ctx[:task_type]) &&
          @config["deliberate"] != false
      end

      def wrap(msg)
        <<~PROMPT
          #{msg}

          Before acting: list #{MIN_OPTIONS} distinct approaches (numbered).
          Each: one-line name + one-line trade-off. Then execute the strongest one.
          State which you chose and why in one sentence.
        PROMPT
      end
    end
  end
  end
end
