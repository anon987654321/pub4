# frozen_string_literal: true

module Master
  module Now
    # TurnRouter — one entry for agent work: plain language → Fold, slash → command_registry.
    module TurnRouter
      module_function

      def call(message:, container:, felt_sense: nil, on_turn: nil)
        text = message.to_s.strip
        return Master::Result.err("empty message", category: :validation) if text.empty?

        if text.start_with?("/")
          dispatch_slash(text, container:, felt_sense:, on_turn:)
        else
          run_fold(text, container:, on_turn:)
        end
      end

      def run_fold(goal, container:, on_turn: nil)
        goal = goal.to_s.strip
        return Master::Result.err(Master.no_api_key_message, category: :no_api_key) unless Master.any_api_key_present?

        root = container[:root] || Dir.pwd
        fold = CoreBridge.run(
          goal,
          root:,
          bus: container[:bus],
          model_id: container[:agent]&.model,
          on_turn:
        )
        fold_to_result(fold)
      rescue StandardError => e
        Master::Result.err("core: #{e.message}", category: :infrastructure)
      end

      def dispatch_slash(input, container:, felt_sense: nil, on_turn: nil)
        ctx = PipelineContext.wrap(user_message: input, felt_sense:)
        ctx = unwrap(Stages::Intake.new.call(ctx))
        return ctx if ctx.is_a?(Master::Result)

        if ctx.intent == :llm
          goal = ctx.message.to_s.strip
          goal = input.to_s.strip if goal.empty?
          return run_fold(goal, container:, on_turn:)
        end

        commands = container[:commands]
        return Master::Result.err("command: registry unavailable", category: :infrastructure) unless commands

        agent = container[:agent]
        bus = container[:bus]
        renderer = container[:renderer]
        ctx = unwrap(Stages::Route.new(commands:, agent:, bus:).call(ctx))
        return ctx if ctx.is_a?(Master::Result)

        ctx = unwrap(Stages::DestructiveReview.new(deliberation: container[:deliberation], event_bus: bus).call(ctx))
        return ctx if ctx.is_a?(Master::Result)

        ctx = unwrap(Stages::Execute.new.call(ctx))
        return ctx if ctx.is_a?(Master::Result)

        Stages::Render.new(
          renderer:,
          output_check: container[:output_check],
          event_bus: bus
        ).call(ctx)
      rescue StandardError => e
        Master::Result.err("command: #{e.message}", category: :infrastructure)
      end

      def fold_to_result(fold)
        text = fold_output_text(fold)
        value = { output: text, rendered: text, core: fold }
        return Master::Result.ok(value) if fold[:reason] == :complete

        Master::Result.err(text, category: :policy)
      end

      def fold_output_text(fold)
        header = "core: #{fold[:reason]} turns=#{fold[:turns]}"
        [header, *fold[:transcript], fold[:summary]].compact.join("\n")
      end

      def unwrap(result)
        return result unless result.ok?

        result.value!
      end
    end
  end
end