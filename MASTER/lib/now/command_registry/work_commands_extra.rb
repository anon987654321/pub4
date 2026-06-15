# frozen_string_literal: true

require_relative "../tribunal_feedback"

module Master
  module Now
    module CommandRegistry
      module_function

      def dispatch_review(council_stage:, deliberation:, root:, bus:, review_crew:, ctx: nil)
        arg = arg_for(ctx)
        case arg
        when "on"     then council_stage.enable!; "review: enabled in pipeline"
        when "off"    then council_stage.disable!; "review: disabled in pipeline"
        when "status" then "review: #{council_stage.enabled? ? "on" : "off"} in pipeline"
        else
          target = arg.empty? ? "." : arg
          crew_result = review_crew&.run(target: target)
          artifact = snapshot_artifact(expand_or_root(target, root))
          crew_text = if crew_result&.ok?
                        crew_result.value![:summary].to_s
                      elsif crew_result
                        crew_result.message.to_s
                      end
          review_text = run_tribunal(deliberation:, artifact:, target:, bus:)
          [crew_text, review_text].compact.reject(&:empty?).join("\n\n")
        end
      end

      # Scan → fix dry-run → council deliberation. Invoked via infer/workflow intent, not user-facing /triad.
      def dispatch_workflow(scanner:, fix_loop:, deliberation:, root:, bus:, ctx: nil, **_legacy)
        target = arg_for(ctx).to_s.strip.empty? ? "." : arg_for(ctx).to_s.strip
        abs = expand_or_root(target, root)
        artifact = snapshot_artifact(abs)
        [
          "workflow: scan",
          dispatch_scan(scanner:, root:, ctx: { args: target }),
          "",
          "workflow: fix dry-run",
          dispatch_fix(fix_loop:, root:, ctx: { args: "--dry-run #{target}" }),
          "",
          "workflow: deliberation",
          run_tribunal(deliberation:, artifact:, target:, bus:)
        ].join("\n")
      end

      def dispatch_triad(**kwargs)
        dispatch_workflow(**kwargs)
      end

      def run_tribunal(deliberation:, artifact:, target:, bus: nil)
        run_deliberation(deliberation:, payload: artifact, context: target) { |feedback| TribunalFeedback.new(feedback, event_bus: bus).render }
      rescue StandardError => e
        "tribunal: #{e.message}"
      end

      def run_deliberation(deliberation:, payload:, context:)
        return "deliberation: not configured" unless deliberation

        result = deliberation.review_convergent(payload, context:)
        return result.message if result.err?

        yield result.value!
      end

      def snapshot_artifact(abs_path)
        return "not found: #{abs_path}" unless File.exist?(abs_path)
        return File.read(abs_path).b[0, SNAPSHOT_FILE_BYTES] if File.file?(abs_path)

        files = Dir.glob(File.join(abs_path, "**/*.{rb,erb,yml}")).first(SNAPSHOT_DIR_FILE_LIMIT)
        files.map { |f|
          "--- #{f.sub(abs_path + "/", "")} ---\n#{File.read(f).b[0, SNAPSHOT_DIR_FILE_BYTES]}"
        }.join("\n\n")[0, SNAPSHOT_DIR_TOTAL_BYTES]
      end

      def dispatch_critique(deliberation:, root:, ctx: nil)
        arg = arg_for(ctx)
        return "usage: /critique <file|text>" if arg.empty?
        path = File.expand_path(arg, root)
        payload = File.exist?(path) ? File.read(path, encoding: "UTF-8") : arg
        run_deliberation(deliberation:, payload:, context: "explicit /critique session") { |feedback|
          TribunalFeedback.new(feedback).render_full
        }
      end

      def dispatch_model(agent:, config:, metrics:, root:, ctx: nil, arg: nil)
        arg = arg || arg_for(ctx)
        return list_models(root:, metrics:, agent:) if arg == "list"
        return "model: #{agent.model} (use /model list for available models)" if arg.empty?
        agent.model = arg; config.save!; "model: #{arg}"
      end

      def list_models(root:, metrics:, agent:)
        yml_path = File.join(root, "data", "models.yml")
        return "model: #{agent.model}" unless File.exist?(yml_path)
        data = Master.load_yaml(yml_path)
        tiers = data["models"] || {}
        current = agent.model.to_s
        model_lines = tiers.flat_map do |tier, ms|
          ms.to_a.map do |mod|
            marker = mod["id"].to_s == current ? "→ " : "  "
            "#{marker} [#{tier}] #{mod["id"]}"
          end
        end
        quality_lines = metrics&.model_quality&.map { |mod, stat|
          "  #{mod}: #{stat[:calls]} calls, fail_rate=#{stat[:fail_rate]}"
        } || []
        sections = ["available models:"] + model_lines
        sections += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
        sections.join("\n")
      end

      def dispatch_why(agent:, root:, ctx: nil)
        rule = arg_for(ctx)
        return "usage: /why <law|scan_rule|anti_pattern|style.key>" if rule.empty?
        local = Trace::WhyExplainer.new(root:).explain(rule)
        return local if local
        agent.ask_once(Voice::Personality.why_prompt(rule))
      end

      def dispatch_ecology(ecology, ctx: nil)
        arg = arg_for(ctx)
        return "ecology: not wired" unless ecology
        path = arg.to_s.strip.empty? ? nil : File.expand_path(arg.strip)
        report = ecology.scan(path: path)
        ecology.render(report)
      rescue StandardError => e
        "ecology: #{e.message}"
      end

      def dispatch_topic(session, ctx: nil)
        arg = arg_for(ctx)
        if arg.empty?
          current = session.respond_to?(:topic) ? session.topic : nil
          current ? "topic: #{current}" : "no topic set  /topic <description>"
        else
          session.topic = arg if session.respond_to?(:topic=)
          "topic: #{arg}"
        end
      end

      def arg_for(ctx) = ctx.to_h.fetch(:args, "").to_s.strip
    end
  end
end
