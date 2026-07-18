# frozen_string_literal: true

require_relative "../../core/master"
require_relative "../io/media_intent"

module Master
  module CLI
    # TurnRouter — one entry for agent work: plain language → Fold, slash → command_registry.
    module TurnRouter
      module_function

      def call(message:, container:, felt_sense: nil, on_turn: nil, on_chunk: nil)
        text = message.to_s.strip
        return Master::Result.err("empty message", category: :validation) if text.empty?

        if text.start_with?("/")
          dispatch_slash(text, container:, felt_sense:, on_turn:)
        elsif Master::Io::MediaIntent.handles?(text)
          Master::Io::MediaIntent.dispatch(text, root: container.fetch(:root, Dir.pwd))
        elsif casual?(text)
          casual_reply(text, container:, felt_sense:, on_chunk:)
        else
          run_fold(text, container:, on_turn:)
        end
      end

      # Core::Fold's constitution requires exec evidence (test_pass, scan_clean,
      # ...) before it admits a `done` effect — right for a coding goal, but
      # it means the Fold can never answer "hi" alone. Plain conversation (no
      # recognized coding-task keyword, no risk-pattern hit) skips the Fold
      # entirely and talks straight to the agent, which already carries the
      # persona system prompt, model routing, and visitor-scoped tools
      # (AskLlm/WebSearch — see Fiber[:master_visitor] in tool_registry.rb).
      def casual?(text)
        return false if text.match?(FoldRisk::HIGH_PATTERNS) || text.match?(FoldRisk::MEDIUM_PATTERNS)

        Ground::IntentRouter.new.classify(text) == :unknown
      end

      def casual_reply(text, container:, felt_sense: nil, on_chunk: nil)
        return Master::Result.err(Master.no_api_key_message, category: :no_api_key) unless Master.any_api_key_present?

        agent = container[:agent]
        return Master::Result.err("agent unavailable", category: :infrastructure) unless agent

        result = agent.call({ message: text, on_chunk:, felt_sense:, task_type: "chat" })
        return result if result.is_a?(Master::Result::Err)

        reply = result.value!.to_s
        Master::Result.ok({ output: reply, rendered: reply })
      rescue StandardError => e
        Master::Result.err("chat: #{e.message}", category: :infrastructure)
      end

      def run_fold(goal, container:, on_turn: nil)
        goal = goal.to_s.strip
        return Master::Result.err(Master.no_api_key_message, category: :no_api_key) unless Master.any_api_key_present?

        root, risk = assess_fold_risk(goal, container:)
        memory = prepare_fold_memory(goal:, container:, risk:)
        fold_to_result(run_fold_pipeline(goal, root:, container:, on_turn:, memory:, risk:))
      rescue StandardError => e
        Master::Result.err("core: #{e.message}", category: :infrastructure)
      end

      def assess_fold_risk(goal, container:)
        root = container.fetch(:root, Dir.pwd)
        assessment = FoldRisk.assess(goal, root:)
        risk = assessment[:risk]
        container[:bus]&.publish("fold:risk", risk:, intent: assessment[:intent])
        [root, risk]
      end

      def run_fold_pipeline(goal, root:, container:, on_turn:, memory:, risk:)
        CoreBridge.run(
          goal,
          root:,
          bus: container[:bus],
          model_id: container[:agent]&.model,
          on_turn:,
          memory:,
          container:,
          risk:
        )
      end

      def prepare_fold_memory(goal:, container:, risk:)
        memory = Master::Core::Memory.new(risk:)
        memory.note(:risk, risk)
        ideation = DeliberationPrep.prepare!(goal:, container:, risk:)
        if ideation
          DeliberationPrep.seed_memory!(memory, ideation)
        elsif FoldRisk.ideation_required?(risk)
          memory.note(:chosen, "proceed: ideation skipped (no agent)")
          memory.mark_ideation_complete!
        end
        memory
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

        run_command_pipeline(ctx, container:, commands:)
      rescue StandardError => e
        Master::Result.err("command: #{e.message}", category: :infrastructure)
      end

      def run_command_pipeline(ctx, container:, commands:)
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
      end

      def fold_to_result(fold)
        text = fold_output_text(fold)
        value = { output: text, rendered: text, core: fold }
        return Master::Result.ok(value) if fold[:reason] == :complete

        Master::Result.err(text, category: :policy)
      end

      def fold_output_text(fold)
        header = "core: #{fold[:reason]} turns=#{fold[:turns]}"
        header += " risk=#{fold[:risk]}" if fold[:risk]
        [header, *fold[:transcript], fold[:summary]].compact.join("\n")
      end

      def unwrap(result)
        return result unless result.ok?

        result.value!
      end
    end
  end
end
