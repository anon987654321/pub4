# frozen_string_literal: true

module Master
  module CLI
    # TurnPipeline — pipeline-shaped adapter over TurnRouter (slice 5 cutover).
    # Keeps :pipeline in the container for gateway, standing orders, and timings hooks
    # without booting the legacy multi-stage LLM pipeline.
    class TurnPipeline
      def initialize(container:)
        @container = container
      end

      attr_reader :container

      def call(initial)
        wrapped = initial.is_a?(Master::Result) ? initial : Master::Result.wrap(initial)
        return wrapped if wrapped.err?

        value = wrapped.value!
        ctx = value.is_a?(Hash) ? value : { user_message: value.to_s }
        message = ctx[:user_message].to_s.strip
        return Master::Result.err("pipeline: empty message", category: :validation) if message.empty?

        TurnRouter.call(
          message:,
          container: @container,
          felt_sense: ctx[:felt_sense],
          image: ctx[:image],
        )
      end

      def last_timings = {}
    end
  end
end
