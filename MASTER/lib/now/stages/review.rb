# frozen_string_literal: true

module Master
  module Now
    module Stages
      # Review — one post-execution pass for council feedback, lint, and pruning.
      class Review
        def initialize(council:, scanner:, config:, root: nil, event_bus: nil, **_)
          @council = council
          @lint = Lint.new(scanner:, config:, root:, event_bus:)
          @prune = Prune.new
          @bus = event_bus
        end

        def call(ctx)
          ctx = run_council(ctx)
          ctx = run_stage(@lint, ctx).value_or(ctx)
          run_stage(@prune, ctx)
        rescue StandardError => e
          @bus&.publish("review:error", message: e.message)
          Result.ok(ctx.merge(review_error: e.message))
        end

        private

        def run_council(ctx)
          return ctx unless @council

          group = Master::Now::Pipeline::ParallelGroup.new(@council, bus: @bus)
          run_stage(group, ctx).value_or(ctx)
        end

        def run_stage(stage, ctx)
          result = stage.call(ctx)
          return result if result.respond_to?(:ok?) && !result.ok?

          Result.wrap(result).map { |value| value || ctx }
        rescue StandardError => e
          @bus&.publish("review:stage_error", stage: stage.class.name, message: e.message)
          Result.ok(ctx)
        end
      end
    end
  end
end
