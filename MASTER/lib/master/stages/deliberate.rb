# frozen_string_literal: true

module Master
  module Stages
    # Deliberate — adversarial pre-execution stage for coding tasks.
    #
    # Forces the agent to enumerate N distinct approaches before committing
    # to one implementation. Prevents first-solution fixation. Disabled for
    # commands, queries, and non-coding intents.
    class Deliberate
      MIN_OPTIONS   = 4
      CODING_TYPES  = %i[coding].freeze

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

          Before writing any code: list #{MIN_OPTIONS} distinct implementation approaches (numbered). Each: one-line name + one-line trade-off. Then implement the strongest one. State which you chose and why in one sentence.
        PROMPT
      end
    end
  end
end
