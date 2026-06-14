# frozen_string_literal: true

require "json"
require "open3"
require "set"
require "time"
require_relative "../../trace/event_log"
require_relative "formatter"
require_relative "../fix_preview_report"
require_relative "../resync_service"
require_relative "../scan_report"
require_relative "../scan_request"
require_relative "../../judge/review_crew"
require_relative "../tribunal_feedback"

module Master
  module Now
    module CommandRegistry
      module_function

      VIOLATION_TRUNCATE = Master::VIOLATION_TRUNCATE
      SNAPSHOT_FILE_BYTES = 8_000
      SNAPSHOT_DIR_FILE_BYTES = 1_200
      SNAPSHOT_DIR_TOTAL_BYTES = 32_000
      SNAPSHOT_DIR_FILE_LIMIT = 40
      SCAN_RULE_GROUP_LIMIT = 10

      def work_commands(ai:, root:, infra:)
        scanner = ai[:scanner]
        fix_loop = ai[:fix_loop]
        ecology = ai[:ecology]
        deliberation = ai[:deliberation]
        council_stage = ai[:council_stage]
        agent = ai[:agent]
        session = infra[:session]
        bus = infra[:bus]
        review_crew = Judge::ReviewCrew.new(agent: agent, event_bus: bus, root: root, code_index: ai[:code_index], reference_graph: ai[:reference_graph])
        propose_tree = ai[:propose_tree]
        config = infra[:config]
        metrics = infra[:metrics]
        git = ai[:git] || Reach::GitOperations.new(File.expand_path("..", root))
        {
          "scan" => command { |ctx| dispatch_scan(scanner:, root:, arg: arg_for(ctx)) },
          "self" => command { |_ctx| dispatch_self(scanner:, root:, bus:) },
          "fix" => command { |ctx| dispatch_fix(fix_loop:, root:, arg: arg_for(ctx)) },
          "status" => command { |_c| dispatch_status(root:, fix_loop:, bus:, git:) },
          "resync" => command { |c| dispatch_resync(root:, fix_loop:, git:, arg: arg_for(c)) },
          "tail" => command { |c| dispatch_tail(root:, arg: arg_for(c)) },
          "review" => command { |ctx| dispatch_review(council_stage:, deliberation:, root:, bus:, review_crew:, arg: arg_for(ctx)) },
          "critique" => command { |ctx| dispatch_critique(deliberation:, root:, arg: arg_for(ctx)) },
          "triad" => command { |ctx| dispatch_triad(scanner:, fix_loop:, council_stage:, deliberation:, root:, bus:, review_crew:, arg: arg_for(ctx)) },
          "model" => command { |c| dispatch_model(agent:, config:, metrics:, root:, arg: arg_for(c)) },
          "why" => command { |ctx| dispatch_why(agent:, root:, rule: arg_for(ctx)) },
          "axioms" => command { |ctx| dispatch_axioms(scanner:, root:, arg: arg_for(ctx)) },
          "rules" => command { |ctx| dispatch_rules(arg_for(ctx)) },
          "topic" => cmd(:dispatch_topic, session),
          "process" => command { |_c| JSON.pretty_generate(process: Master::Ops::ProcessBudget.status, loop_slot: Master::Ops::LoopSlot.status) },
          "propose-tree" => command { |_ctx| propose_tree&.call || "propose-tree: not wired" },
          "ecology" => command { |ctx| dispatch_ecology(ecology, arg_for(ctx)) }
        }
      end

      def dispatch_self(scanner:, root:, bus:)
        result = Master::Judge::Scan::SelfScan.new(scanner:, root:, event_bus: bus).call(stream: true, autofix: true)
        return result.message unless result.ok?

        result.value!.line
      end

      # /status — one-frame health panel. Replaces seven probing tool calls.
      def dispatch_status(root:, fix_loop:, bus:, git: Reach::GitOperations.new(File.expand_path("..", root)))
        ahead, behind = git.ahead_behind
        head = git.head || "?"
        dirty = git.dirty?(".")
        svc = service_status
        bg = fix_loop&.background_alive? ? "running" : "stopped"
        af = ENV["MASTER_AUTOFIX"] == "1" ? "on" : "off"
        bndl = bundle_status(File.expand_path("..", root))
        evts = recent_events(root, 5)
        branch = git.branch || "?"
        lines = [
          "status",
          "service master/#{svc[:state]} #{svc[:detail]}",
          "git     #{branch}@#{head} ahead=#{ahead} behind=#{behind} #{dirty ? "dirty" : "clean"}",
          "fix     bg=#{bg} autofix=#{af}",
          "bundle  #{bndl}",
          "events  (last #{evts.size})"
        ]
        evts.each { |e| lines << "  #{e[:ago]} #{e[:event]} #{e[:summary]}" }
        lines.join("\n")
      rescue StandardError => e
        "status: #{e.message}"
      end

      def service_status
        out, _, st = Open3.capture3("/usr/sbin/rcctl", "check", "master")
        { state: st.success? ? "ok" : "down", detail: out.strip }
      rescue Errno::ENOENT
        { state: "n/a", detail: "rcctl absent — not OpenBSD" }
      rescue StandardError => e
        { state: "?", detail: "rcctl err: #{e.class}: #{e.message[0, 60]}" }
      end

      def bundle_ok?(dir)
        out, = Open3.capture2e("bundle34", "check", chdir: dir)
        out.include?("dependencies are satisfied")
      end

      def bundle_status(repo)
        mas_ok = bundle_ok?(File.join(repo, "MASTER"))
        web_ok = bundle_ok?(File.join(repo, "MASTER/web"))
        mas_ok && web_ok ? "ok (MASTER+web satisfied)" : "drift — run bundle install"
      rescue StandardError => e
        "unknown (#{e.class})"
      end

      def recent_events(root, n)
        now = Time.now.utc
        Trace::EventLog.new(root:).recent(n).map { |rec|
          ts = (Time.parse(rec["timestamp"]) rescue now)
          secs = (now - ts).to_i.abs
          ago = secs < 60 ? "#{secs}s" : (secs < 3600 ? "#{secs / 60}m" : "#{secs / 3600}h")
          pay = rec["payload"]
          sum = pay.is_a?(Hash) ? pay.first(3).map { |k, v| "#{k}=#{v.to_s.tr('"', "")[0, 24]}" }.join(" ") : pay.to_s
          { ago: ago.rjust(4), event: rec["event"].to_s, summary: sum[0, 80] }
        }.compact
      rescue StandardError
        []
      end

      # /resync — divergence repair: tag, fetch, reset, bundle, restart.
      def dispatch_resync(root:, fix_loop:, git:, arg:)
        ResyncService.new(root:, fix_loop:, git:).call(dry_run: arg.include?("--dry-run"))
      end

      # /tail [N] [pattern] — last N events matching pattern. Default N=20.
      def dispatch_tail(root:, arg:)
        n_arg, pattern = arg.split(/\s+/, 2)
        n = n_arg.to_i.positive? ? n_arg.to_i : 20
        records = Trace::EventLog.new(root:).tail(n, pattern:)
        return "tail: no events" if records.empty?

        records.map { |rec|
          ts = rec["timestamp"].to_s.sub(/\..+/, "").sub("T", " ")
          "#{ts} #{rec["event"].ljust(28)} #{format_payload(rec["payload"])}"
        }.compact.join("\n")
      rescue StandardError => e
        "tail: #{e.message}"
      end

      def format_payload(pay)
        return pay.to_s[0, 100] unless pay.is_a?(Hash)

        Formatter.key_value_payload(pay)[0, 100]
      end

      def dispatch_fix(fix_loop:, root:, arg:)
        sub, rest = arg.split(/\s+/, 2)
        case sub
        when "--dry-run"
          result = fix_loop.preview(expand_or_root(rest.to_s.strip, root))
          return "fix dry-run: #{result.message}" unless result.ok?
          FixPreviewReport.new(result.value!).render
        when "loop"
          "fix loop: use /watch on for background watching"
        when "stop"
          "fix stop: use /watch off for background watching"
        when "preview"
          result = fix_loop.preview(expand_or_root(rest.to_s.strip, root))
          return "fix preview: #{result.message}" unless result.ok?
          FixPreviewReport.new(result.value!).render
        else
          target = expand_or_root(arg, root)
          result = fix_loop.run(target)
          result.ok? ? result.value! : "fix: #{result.message}"
        end
      end

      # Constitutional scoreboard: per-axiom violation counts over lib/, plus a
      # rule dep-graph completeness report.
      AXIOM_SCAN_CAP = 400

      def dispatch_axioms(scanner:, root:, arg: nil)
        files = axiom_scan_files(root)
        by_axiom = tally_axioms(scanner, files)
        [axiom_table(files, by_axiom), "", dep_graph_line(root)].join("\n")
      end

      def axiom_scan_files(root)
        Dir.glob(File.join(root, "lib", "**", "*.rb"))
           .reject { |p| p.include?("/knowledge/") || p.include?("/vendor/") }
           .sort.first(AXIOM_SCAN_CAP)
      end

      def tally_axioms(scanner, files)
        files.each_with_object(Hash.new(0)) do |path, acc|
          result = scanner.scan(path, depth: :deep)
          next unless result.ok?
          result.value!.each { |f| Array(f[:tags]).each { |t| acc[t.to_s] += 1 } }
        end
      end

      def axiom_table(files, by_axiom)
        head = "constitution — #{files.size} files scanned"
        return "#{head}\n  clean: no axiom violations" if by_axiom.empty?
        rows = by_axiom.sort_by { |_, n| -n }.map { |tag, n| "  #{tag.ljust(24)} #{n}" }
        ([head] + rows + ["  total#{" " * 19}#{by_axiom.values.sum}"]).join("\n")
      end

      def dep_graph_line(root)
        gap = ungraphed_rules(root)
        tail = gap.empty? ? " (complete)" : " — #{gap.first(8).join(", ")}"
        "rule dep-graph: #{gap.size} rule(s) absent from rule_deps.yml#{tail}"
      end

      def dispatch_rules(arg)
        return "usage: /rules list" unless arg.empty? || arg == "list"

        Master::Judge::Scan::Rule.registry.map do |rule_class|
          rule = rule_class.new
          severity = rule.respond_to?(:severity) ? rule.severity : "?"
          "#{rule.id.to_s.ljust(28)} #{severity.to_s.ljust(8)} #{rule_class.name}"
        end.sort.join("\n")
      rescue StandardError => e
        "rules: #{e.message}"
      end

      def ungraphed_rules(root)
        rule_classes = Master::Judge::Scan::Rule.registry
        registered = rule_classes.map do |rule_class|
          rule = rule_class.new
          rule.id.upcase
        end.uniq
        graph = (Master.load_yaml(File.join(root, "data", "rule_deps.yml")) || {})["deps"] || {}
        graph_after_rules = graph.values.flat_map { |v| Array(v["after"]) }
        graphed = (graph.keys + graph_after_rules).map(&:to_s).uniq
        (registered - graphed).sort
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "command_registry.ungraphed_rules")
        []
      end

      def dispatch_scan(scanner:, root:, arg:)
        dry_run = dry_run_arg?(arg)
        request = ScanRequest.new(scanner:, root:, arg: strip_dry_run(arg)).call
        return request.pairs if request.pairs.is_a?(String)
        ScanReport.new(
          pairs: request.pairs,
          profile: request.profile,
          rule_filter: request.rule_filter,
          severity_filter: request.severity_filter,
          dry_run: dry_run
        ).render
      end

      def dry_run_arg?(arg)
        arg.to_s.split(/\s+/).include?("--dry-run")
      end

      def strip_dry_run(arg)
        arg.to_s.split(/\s+/).reject { |part| part == "--dry-run" }.join(" ")
      end

      def dispatch_review(council_stage:, deliberation:, root:, bus:, review_crew:, arg:)
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

      def dispatch_triad(scanner:, fix_loop:, council_stage:, deliberation:, root:, bus:, review_crew:, arg:)
        target = arg.to_s.strip.empty? ? "." : arg.to_s.strip
        [
          "triad: scan",
          dispatch_scan(scanner:, root:, arg: target),
          "",
          "triad: fix dry-run",
          dispatch_fix(fix_loop:, root:, arg: "--dry-run #{target}"),
          "",
          "triad: review",
          dispatch_review(council_stage:, deliberation:, root:, bus:, review_crew:, arg: target)
        ].join("\n")
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

      def dispatch_critique(deliberation:, root:, arg:)
        return "usage: /critique <file|text>" if arg.empty?
        path = File.expand_path(arg, root)
        payload = File.exist?(path) ? File.read(path, encoding: "UTF-8") : arg
        run_deliberation(deliberation:, payload:, context: "explicit /critique session") { |feedback|
          TribunalFeedback.new(feedback).render_full
        }
      end

      def dispatch_model(agent:, config:, metrics:, root:, arg:)
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

      def dispatch_why(agent:, root:, rule:)
        return "usage: /why <law|scan_rule|anti_pattern|style.key>" if rule.empty?
        local = Trace::WhyExplainer.new(root:).explain(rule)
        return local if local
        agent.ask_once(Voice::Personality.why_prompt(rule))
      end

      def dispatch_ecology(ecology, arg)
        return "ecology: not wired" unless ecology
        path = arg.to_s.strip.empty? ? nil : File.expand_path(arg.strip)
        report = ecology.scan(path: path)
        ecology.render(report)
      rescue StandardError => e
        "ecology: #{e.message}"
      end

      def dispatch_topic(session, arg)
        if arg.empty?
          current = session.respond_to?(:topic) ? session.topic : nil
          current ? "topic: #{current}" : "no topic set  /topic <description>"
        else
          session.topic = arg if session.respond_to?(:topic=)
          "topic: #{arg}"
        end
      end
    end
  end
end
