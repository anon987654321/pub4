# frozen_string_literal: true

module Master
  module Now
    class CLI
      private

      # Slash input: Intake → Route → DestructiveReview → Execute → Render.
      # /run <goal> promotes to :llm and falls through to the core Fold.
      def run_slash_dispatch(input, state:, accumulated:)
        ctx = PipelineContext.wrap(user_message: input, felt_sense: cli_felt_sense)
        ctx = step_result(Stages::Intake.new.call(ctx))
        return ctx if ctx.is_a?(Master::Result)

        if ctx.intent == :llm
          goal = ctx.message.to_s.strip
          goal = input.to_s.strip if goal.empty?
          return run_core_bridge_input(goal, state:, accumulated:)
        end

        commands = @container[:commands]
        return Master::Result.err("command: registry unavailable", category: :infrastructure) unless commands

        ctx = step_result(Stages::Route.new(commands:, agent: @refs.agent, bus: @refs.bus).call(ctx))
        return ctx if ctx.is_a?(Master::Result)

        ctx = step_result(
          Stages::DestructiveReview.new(deliberation: @container[:deliberation], event_bus: @refs.bus).call(ctx)
        )
        return ctx if ctx.is_a?(Master::Result)

        ctx = step_result(Stages::Execute.new.call(ctx))
        return ctx if ctx.is_a?(Master::Result)

        Stages::Render.new(
          renderer: @refs.renderer,
          output_check: @container[:output_check],
          event_bus: @refs.bus
        ).call(ctx)
      rescue StandardError => e
        Master::Result.err("command: #{e.message}", category: :infrastructure)
      end

      def step_result(result)
        return result unless result.ok?

        result.value!
      end
    end
  end
end