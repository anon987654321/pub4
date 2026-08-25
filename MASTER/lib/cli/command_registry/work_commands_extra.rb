# frozen_string_literal: true

require_relative "../tribunal_feedback"
require_relative "../../review/council/critique"

module Master
  module CLI
    module CommandRegistry
      module_function

      SNAPSHOT_EXTENSIONS = %w[.rb .erb .yml].freeze
      SNAPSHOT_SKIP_SEGMENTS = %w[
        .git .bundle node_modules vendor tmp log coverage storage cache dist build knowledge public var
      ].freeze

      def dispatch_review(deliberation:, root:, bus:, review_crew:, ctx: nil)
        review_target(arg_for(ctx), root:, deliberation:, bus:, review_crew:)
      end

      def review_target(arg, root:, deliberation:, bus:, review_crew:)
        target = arg.empty? ? "." : arg
        crew_result = review_crew&.run(target:)
        artifact = snapshot_artifact(expand_or_root(target, root))
        crew_text = if crew_result&.ok?
                      crew_result.value![:summary].to_s
                    elsif crew_result
                      crew_result.message.to_s
                    end
        review_text = run_tribunal(deliberation:, artifact:, target:, bus:)
        [crew_text, review_text].compact.reject(&:empty?).join("\n\n")
      end

      # Full singularity sequence (aesthetic → scan → fix → re-scan → critique).
      # Invoked by natural-language inference, /workflow, /through, /triad — users need not memorize stages.
      def dispatch_workflow(scanner:, fix_loop:, deliberation:, root:, bus:, ctx: nil, review_crew: nil, **_legacy)
        raw = arg_for(ctx).to_s.strip
        apply, critique, aesthetic, target = parse_through_flags(raw)
        Master::CLI::ThroughPipeline.new(
          scanner:,
          fix_loop:,
          root:,
          deliberation:,
          bus:,
          review_crew:,
        ).call(target:, apply:, critique:, aesthetic:).render
      end

      def dispatch_through(scanner:, fix_loop:, deliberation:, root:, bus:, ctx: nil, review_crew: nil, **_legacy)
        dispatch_workflow(
          scanner:, fix_loop:, deliberation:,
          root:, bus:, ctx:, review_crew:
        )
      end

      def parse_through_flags(raw)
        apply = nil
        critique = nil
        aesthetic = true
        tokens = raw.split(/\s+/)
        path_bits = []
        tokens.each do |tok|
          case tok.downcase
          when "--dry-run", "preview", "dry" then apply = false
          # bin/gate's scan-only spelling. Unrecognised, it fell into the
          # path, resolved nowhere, and the scan quietly ran over MASTER.
          when "--no-autofix", "no-autofix" then apply = false
          when "--apply", "apply", "fix" then apply = true
          when "--no-critique", "no-critique" then critique = false
          when "--critique", "critique" then critique = true
          when "--no-aesthetic", "no-aesthetic" then aesthetic = false
          else path_bits << tok
          end
        end
        [apply, critique, aesthetic, path_bits.join(" ")]
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
        return snapshot_truncate(File.read(abs_path), SNAPSHOT_FILE_BYTES) if File.file?(abs_path)

        files = snapshot_files(abs_path)
        files.map do |f|
          "--- #{f.sub(abs_path + "/", "")} ---\n#{snapshot_truncate(File.read(f), SNAPSHOT_DIR_FILE_BYTES)}"
        end.join("\n\n")[0, SNAPSHOT_DIR_TOTAL_BYTES]
      end

      # Byte-truncate via .b (so a byte limit can't be exceeded by a
      # multi-byte char) but re-tag as UTF-8 and scrub afterward -- callers
      # concatenate this into UTF-8 prompt text, and a truncation boundary
      # landing mid-character otherwise raises Encoding::CompatibilityError
      # the moment it's joined with anything not itself forced to BINARY
      # (confirmed live: every /critique persona failing with exactly that
      # error, tracing back to this truncation never restoring the tag).
      def snapshot_truncate(text, byte_limit)
        text.b[0, byte_limit].force_encoding("UTF-8").scrub
      end

      def snapshot_files(abs_path)
        pending = [abs_path]
        files = []
        until pending.empty? || files.size >= SNAPSHOT_DIR_FILE_LIMIT
          scan_snapshot_dir(pending.shift, pending, files)
        end
        files
      end

      def scan_snapshot_dir(current, pending, files)
        Dir.children(current).sort.each do |entry|
          path = File.join(current, entry)
          next if snapshot_skip_path?(path)

          add_snapshot_entry(path, pending, files)
          break if files.size >= SNAPSHOT_DIR_FILE_LIMIT
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.scan_snapshot_dir")
        nil
      end

      def add_snapshot_entry(path, pending, files)
        return pending << path if File.directory?(path)

        files << path if snapshot_file?(path)
      end

      def snapshot_skip_path?(path)
        segments = path.split(File::SEPARATOR)
        SNAPSHOT_SKIP_SEGMENTS.any? { |segment| segments.include?(segment) }
      end

      def snapshot_file?(path)
        File.file?(path) && SNAPSHOT_EXTENSIONS.include?(File.extname(path))
      end

      def dispatch_critique(deliberation:, root:, ctx: nil)
        arg = arg_for(ctx)
        return "usage: /critique <file|text>" if arg.empty?
        path = expand_or_root(arg, root)
        # respond_to?, not `&.agent` — the safe-navigation operator guards a nil
        # deliberation but not a deliberation that has no agent (lean
        # boot, or a test double), which raised NoMethodError from here.
        has_agent = deliberation.respond_to?(:agent) && deliberation.agent
        return general_council_critique(deliberation, path) if has_agent && File.exist?(path)

        payload = File.exist?(path) ? snapshot_artifact(path) : arg
        run_deliberation(deliberation:, payload:, context: "explicit /critique session") do |feedback|
          TribunalFeedback.new(feedback).render_full
        end
      end

      # Same persona-panel -> ideation -> cherry-pick pipeline the product
      # critiques (ui/sound/dilla) use, generalized to whatever /scan or
      # /fix just processed instead of a fixed file list.
      def general_council_critique(deliberation, path)
        files = File.directory?(path) ? snapshot_files(path) : [path]
        return "critique: no reviewable files under #{path}" if files.empty?

        critic = Master::Review::Council::Critique.new(
          mode: :general, agent: deliberation.agent, event_bus: deliberation.bus, files:,
        )
        result = critic.run
        return "critique: #{result.message}" unless result.ok?

        general_critique_report(result.value!, path)
      rescue StandardError => e
        "critique failed: #{e.class}: #{e.message}"
      end

      def general_critique_report(data, path)
        lines = ["critique #{path}: #{Array(data[:cherry_picks]).size} cherry-pick(s) (MASTER council)"]
        Array(data[:feedback]).each do |f|
          first = f[:feedback].to_s.lines.first.to_s.strip
          lines << "  [#{f[:persona]}] #{first}"
        end
        Array(data[:cherry_picks]).each { |p| lines << "  cherry: #{p}" }
        lines << "  harvested: #{data[:harvest]}" if data[:harvest]
        lines.join("\n")
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
        quality_lines = Array(metrics&.model_quality&.map do |mod, stat|
          "  #{mod}: #{stat[:calls]} calls, fail_rate=#{stat[:fail_rate]}"
        end)
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
        report = ecology.scan(path:)
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

      # Maturity scorecard (OpenClaw's taxonomy.yaml pattern) -- what's
      # actually proven to work, not just claimed. See data/maturity.yml.
      def dispatch_maturity(root:, ctx: nil)
        arg = arg_for(ctx).to_s.strip
        card = Master::Ground::MaturityScorecard.load(root:)
        return card.summary_line if arg.empty?
        return maturity_status_report(card, arg) if Master::Ground::MaturityScorecard::STATUSES.include?(arg)

        entry = card.subsystems.find { |e| e.id == arg }
        return "unknown subsystem #{arg.inspect} — try /maturity, or /maturity verified|smoke|broken" unless entry

        maturity_entry_detail(entry)
      end

      def maturity_status_report(card, status)
        entries = card.by_status(status)
        return "no subsystems with status=#{status}" if entries.empty?

        entries.map { |e| "#{e.id.ljust(36)} #{e.last_checked}  #{e.meaning}" }.join("\n")
      end

      def maturity_entry_detail(entry)
        <<~TEXT.strip
          #{entry.id} — #{entry.status}
          #{entry.meaning}
          last checked: #{entry.last_checked}
          evidence: #{entry.evidence}
        TEXT
      end

      # The 8-law constitutional self-test gate is the single most load-bearing
      # check in the codebase (blocks /fix entirely on any violation), but the
      # law names are Latin-abstract enough that decoding one meant reading
      # self_test.rb itself. Surfaces name -> plain-English meaning ->
      # enforcing method, sourced from the same data/rules.yml the gate
      # actually reads, so this can never drift from what SelfTest enforces.
      def dispatch_laws(root:, ctx: nil)
        arg = arg_for(ctx).to_s.strip.upcase
        laws = Master.load_yaml(File.join(root, "data", "rules.yml")).dig("self_test", "laws_apply_to_self") || {}
        return "no self_test.laws_apply_to_self entries in data/rules.yml" if laws.empty?
        return laws_report(laws) if arg.empty?

        law_detail(laws, arg)
      end

      def laws_report(laws)
        laws.map { |law, meaning| "#{law.ljust(18)} #{meaning}" }.join("\n")
      end

      def law_detail(laws, arg)
        return "unknown law #{arg.inspect} — try /laws for the full list" unless laws.key?(arg)

        "#{arg}\n#{laws[arg]}\nenforced by: Master::Review::Scan::SelfTest (#{LAW_METHODS.fetch(arg, "law_checks")})"
      end

      LAW_METHODS = {
        "ROBUSTNESS" => "bare_rescue_findings (+ deploy/timeout/js-catch/library-verify checks)",
        "SINGULARITY" => "duplicate_rule_id_findings (+ cross-yaml/deploy duplicate-id checks)",
        "LINEARITY" => "structural_findings(NestingDepthRule)",
        "PROXIMITY" => "rule_test_proximity_findings",
        "ABSTRACTION" => "structural_findings(GodClassRule)",
        "DENSITY" => "structural_findings(SmallFunctionsRule)",
        "KERNEL_ADHERENCE" => "kernel_wiring_findings",
        "PRINCIPLE_MAP" => "principle_map_findings",
      }.freeze
    end
  end
end
