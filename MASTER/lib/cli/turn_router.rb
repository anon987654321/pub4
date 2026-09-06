# frozen_string_literal: true

require_relative "../io/media_intent"

module Master
  module CLI
    # TurnRouter — one entry for agent work: plain language → Fold, slash → command_registry.
    module TurnRouter
      module_function

      # Chained elsif nests one IfNode inside the previous one's else-branch,
      # so a 6-way route chain reads flat but is 6 deep in the AST. Guard
      # clauses keep each check a standalone, unnested IfNode.
      def call(message:, container:, felt_sense: nil, on_turn: nil, on_chunk: nil, image: nil)
        text = message.to_s.strip
        return Master::Result.err("empty message", category: :validation) if text.empty?
        return dispatch_slash(rewrite_slash(text), container:, felt_sense:, on_turn:) if text.start_with?("/")

        # Visitors (no web token — i.e. the open internet on ai.brgen.no) get the
        # conversational path only. Everything below this line can reach real
        # capability: infer_operator_command *reconstructs* a slash command from
        # plain English, which defeats the leading-"/" block in
        # chat_controller#message, and run_fold reaches Core::World#do_exec,
        # whose argv/env are model-chosen. Fiber[:master_visitor] previously
        # gated only the advertised LLM tool list (tool_registry.rb), never the
        # Fold or the command registry.
        #
        # MediaIntent used to sit above this gate. "generate a photo" / "make me
        # a beat" / a VHS look on a path then ran repligen/dilla/postpro as the
        # Falcon user and wrote under ~.
        return casual_reply(text, container:, felt_sense:, on_chunk:, image:) if visitor?
        return Master::Io::MediaIntent.dispatch(text, root: container.fetch(:root, Dir.pwd)) if Master::Io::MediaIntent.handles?(text)

        inferred = infer_operator_command(text, container:)
        return dispatch_inferred(inferred, container:, felt_sense:, on_turn:) if inferred
        return dispatch_through_workflow(text, container:, felt_sense:, on_turn:) if full_workflow_intent?(text)
        return casual_reply(text, container:, felt_sense:, on_chunk:, image:) if casual?(text)

        run_fold(text, container:, on_turn:)
      end

      def visitor? = Fiber[:master_visitor] == true

      def dispatch_through_workflow(text, container:, felt_sense: nil, on_turn: nil)
        dispatch_inferred({ command: "through", args: through_args_from(text), confidence: 0.9 }, container:, felt_sense:, on_turn:)
      end

      # Promote plain language to the full pass. Stage names are leftovers.
      THROUGH_COMMANDS = %w[through workflow triad sweep scan fix self critique council review].freeze
      FOLD_SLASH = %w[fold run].freeze
      READ_SLASH = %w[explain why laws axioms principles].freeze
      THROUGH_SLASH = %w[scan fix critique council self workflow triad review sweep].freeze
      INFER_MIN_CONFIDENCE = 0.62

      def infer_operator_command(text, container:)
        value = infer_command_value(text, container:)
        return unless value

        command = value.command.to_s
        conf = value.infer_confidence.to_f
        # Always accept through-class commands; other commands need confidence floor.
        return if !THROUGH_COMMANDS.include?(command) && conf < INFER_MIN_CONFIDENCE

        command = normalize_inferred_command(command, text)
        return if READ_SLASH.include?(command)

        args = command == "through" ? through_command_args(value, text) : value.args.to_s

        { command:, args:, confidence: conf }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "TurnRouter.infer_operator_command")
        nil
      end

      def infer_command_value(text, container:)
        ctx = PipelineContext.build(user_message: text, intent: :llm, message: text)
        inferred = Stages::Infer.new(bus: container[:bus], session: container[:session]).call(ctx)
        return unless inferred.ok?

        value = inferred.value!
        value.intent == :command ? value : nil
      end

      def normalize_inferred_command(command, text)
        return command if text.match?(/--dry-run|--no-autofix|\bpreview\b/i)
        return "through" if THROUGH_COMMANDS.include?(command)

        command
      end

      def through_command_args(value, text)
        args = value.args.to_s
        refined = through_args_from(text)
        # Prefer refined path when Infer only captured a coarse alias (rails without app).
        args = refined if !refined.empty? && (args.empty? || refined.start_with?("#{args}/") || refined != args && refined.include?("/"))
        args = refined if args.empty?
        args = "master" if args.match?(/\A(?:itself|self)\z/i) && text.match?(/\bmaster\b/i)
        args = "master" if args.match?(/\Aitself\z/i)
        args
      end

      def full_workflow_intent?(text)
        route = Ground::IntentRouter.new.route(text)
        route[:intent] == :run_full_workflow ||
          text.match?(/\b(?:through\s+(?:master|itself|rails)|singularity|self[-\s]?apply|run\s+(?:master|rails)\s+through)\b/i)
      end

      def through_args_from(text)
        if (m = text.match(%r{\brails(?:[:/]([\w./-]+))?}i))
          return m[1] ? "rails/#{m[1]}" : "rails"
        end
        if (m = text.match(%r{\bthrough\s+rails(?:[:/]([\w./-]+))?}i))
          return m[1] ? "rails/#{m[1]}" : "rails"
        end
        if text.match?(/\b(?:itself|self)\b/i) && !text.match?(/\brails\b/i)
          return text.match?(/\blib\b/i) ? "self" : "master"
        end
        return "master" if text.match?(/\bmaster\b/i) && !text.match?(/\brails\b/i)
        return "face" if text.match?(/\bface\b|\bweb\s*ui\b/i)

        ""
      end

      def dispatch_inferred(inferred, container:, felt_sense: nil, on_turn: nil)
        command = inferred[:command].to_s
        args = inferred[:args].to_s
        container[:bus]&.publish("infer:auto", command:, args:, confidence: inferred[:confidence])
        slash = args.empty? ? "/#{command}" : "/#{command} #{args}"
        dispatch_slash(slash, container:, felt_sense:, on_turn:)
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

      def casual_reply(text, container:, felt_sense: nil, on_chunk: nil, image: nil)
        return Master::Result.err(Master.no_api_key_message, category: :no_api_key) unless Master.any_api_key_present?

        agent = container[:agent]
        return Master::Result.err("agent unavailable", category: :infrastructure) unless agent

        result = agent.call({ message: text, on_chunk:, felt_sense:, task_type: "chat", image: })
        return result if result.is_a?(Master::Result::Err)

        reply = result.value!.to_s
        Master::Result.ok({ output: reply, rendered: reply })
      rescue StandardError => e
        Master::Result.err("chat: #{e.message}", category: :infrastructure)
      end

      def run_fold(goal, container:, on_turn: nil)
        goal = goal.to_s.strip
        # Defence in depth: TurnRouter.call already routes visitors to
        # casual_reply, but run_fold is also reachable via dispatch_slash when
        # Intake classifies input as :llm. The Fold can exec; visitors cannot.
        return Master::Result.err("fold: not available to visitors", category: :policy) if visitor?
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
          risk:,
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
          memory.proof.mark_ideation_complete!
        end
        memory
      end

      # One verb, named stages. /scan, /fix and /critique are not separate
      # commands and have not been since the registry closed its public surface
      # — but until 2026-09-06 they all rewrote to a bare /through, so asking to
      # scan ran the fix stage and the critique too. Each now carries the stage
      # it names; the words that mean the whole pass still mean the whole pass.
      #
      # The scan stage fixes what it finds, on the spot, which is why /scan and
      # /fix name the same stage: a finding is cheapest to repair at the moment
      # it is found, and a fix loop with no scan in front of it has nothing to
      # act on. `--no-autofix` and `--dry-run` still hold it back.
      STAGE_FOR_SLASH = {
        "scan" => "scan",
        "fix" => "scan",
        "critique" => "critique",
        "council" => "critique",
        "review" => "critique",
      }.freeze

      def rewrite_slash(input)
        name, rest = input.sub(%r{\A/}, "").split(/\s+/, 2)
        name = name.to_s.downcase
        return input unless THROUGH_SLASH.include?(name)

        stage = STAGE_FOR_SLASH[name]
        parts = ["/through", ("--only #{stage}" if stage), rest.to_s.strip].compact.reject(&:empty?)
        parts.join(" ")
      end

      def dispatch_slash(input, container:, felt_sense: nil, on_turn: nil)
        name, rest = input.sub(%r{\A/}, "").split(/\s+/, 2)
        return run_fold(rest.to_s, container:, on_turn:) if FOLD_SLASH.include?(name.to_s.downcase)

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
          event_bus: bus,
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
