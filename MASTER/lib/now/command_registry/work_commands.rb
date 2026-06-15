# frozen_string_literal: true

require "json"
require "open3"
require "set"
require "time"

module Master
  module Now
    module CommandRegistry
      module_function

      VIOLATION_TRUNCATE = Master::VIOLATION_TRUNCATE

      def work_commands(ai:, root:, infra:)
        scanner = ai[:scanner]
        fix_loop = ai[:fix_loop]
        ecology = ai[:ecology]
        deliberation = ai[:deliberation]
        council_stage = ai[:council_stage]
        agent = ai[:agent]
        propose_tree = ai[:propose_tree]
        session = infra[:session]
        bus = infra[:bus]
        config = infra[:config]
        metrics = infra[:metrics]
        {
          "scan" => cmd(:dispatch_scan, scanner, root),
          "self" => ->(_ctx) { dispatch_self(scanner:, root:, bus:) },
          "fix" => ->(ctx) { dispatch_fix(fix_loop, root, arg_for(ctx)) },
          "status" => ->(_c) { dispatch_status(root:, fix_loop:, bus:) },
          "resync" => ->(c) { dispatch_resync(root:, fix_loop:, arg: arg_for(c)) },
          "tail" => ->(c) { dispatch_tail(root:, arg: arg_for(c)) },
          "review" => ->(ctx) { dispatch_review(council_stage:, deliberation:, root:, bus:, arg: arg_for(ctx)) },
          "critique" => cmd(:dispatch_critique, deliberation, root),
          "model" => ->(c) { dispatch_model(agent:, config:, metrics:, root:, arg: arg_for(c)) },
          "why" => cmd(:dispatch_why, agent, root),
          "axioms" => cmd(:dispatch_axioms, scanner, root),
          "topic" => cmd(:dispatch_topic, session),
          "process" => ->(_c) { JSON.pretty_generate(process: Master::Ops::ProcessBudget.status, loop_slot: Master::Ops::LoopSlot.status) },
          "propose-tree" => ->(_ctx) { propose_tree&.call || "propose-tree: not wired" },
          "ecology" => ->(ctx) { dispatch_ecology(ecology, arg_for(ctx)) }
        }
      end

      def dispatch_self(scanner:, root:, bus:)
        result = Master::Judge::Scan::SelfScan.new(scanner:, root:, event_bus: bus).call(stream: true, autofix: true)
        return result.message unless result.ok?

        summary = result.value!
        return "" if summary.violation_count.zero?
        summary.line
      end

      # /status — one-frame health panel. Replaces seven probing tool calls.
      def dispatch_status(root:, fix_loop:, bus:)
        git = Reach::GitOperations.new(File.expand_path("..", root))
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
      rescue StandardError
        false
      end

      def bundle_status(repo)
        mas_ok = bundle_ok?(File.join(repo, "MASTER"))
        web_ok = bundle_ok?(File.join(repo, "MASTER/web"))
        mas_ok && web_ok ? "ok (MASTER+web satisfied)" : "drift — run bundle install"
      rescue StandardError => e
        "unknown (#{e.class})"
      end

      def recent_events(root, n)
        Trace::EventLog.new(root:).recent(n)
      rescue StandardError
        []
      end

      # /resync — divergence repair: tag, fetch, reset, bundle, restart.
      def dispatch_resync(root:, fix_loop:, arg:)
        repo = File.expand_path("..", root)
        git = Reach::GitOperations.new(repo)
        stop_msg = fix_loop&.background_alive? ? (fix_loop.stop_background!; "stopped fix_loop bg; ") : ""
        tag_name = "backup/#{Time.now.strftime("%Y%m%d-%H%M")}-resync"
        old_head = git.head
        lines = ["#{stop_msg}resync starting — tag=#{tag_name} was=#{old_head}"]
        git.tag(tag_name); lines << "  tagged #{tag_name}"
        git.fetch;         lines << "  fetched origin"
        if arg.include?("--dry-run")
          ahead, behind = git.ahead_behind
          return (lines + ["  dry-run: would reset --hard origin/main (ahead=#{ahead} behind=#{behind})"]).join("\n")
        end
        git.reset_hard("origin/main"); lines << "  reset --hard origin/main → #{git.head}"
        lines << bundle_install_line(File.join(repo, "MASTER"), "MASTER")
        lines << bundle_install_line(File.join(repo, "MASTER/web"), "MASTER/web")
        Open3.capture2e("doas", "rcctl", "restart", "master")
        sleep 2
        lines << "  rcctl restart master — #{service_status[:state]}"
        lines.join("\n")
      rescue StandardError => e
        "resync: #{e.message}"
      end

      def bundle_install_line(dir, label)
        out, st = Open3.capture2e("bundle34", "install", chdir: dir)
        ok = st.success? && out.include?("Bundle complete")
        "  bundle install #{label} — #{ok ? "ok" : "FAILED"}"
      rescue StandardError => e
        "  bundle install #{label} — error: #{e.message}"
      end

      # /tail [N] [pattern] — last N events matching pattern. Default N=20.
      def dispatch_tail(root:, arg:)
        n_arg, pattern = arg.split(/\s+/, 2)
        n = n_arg.to_i.positive? ? n_arg.to_i : 20
        log = Trace::EventLog.new(root:)
        return "tail: no event log at #{log.path}" if log.read_lines.empty?
        rx = pattern && !pattern.empty? ? Regexp.new(pattern) : nil
        log.tail(n, pattern:).filter_map { |rec|
          CommandRegistry::Formatter.format_event_line(rec, rx:)
        }.join("\n")
      rescue StandardError => e
        "tail: #{e.message}"
      end

      def format_payload(pay)
        CommandRegistry::Formatter.format_payload(pay)
      end

      def dispatch_fix(fix_loop, root, arg)
        if arg.include?("--dry-run")
          preview_arg = arg.gsub("--dry-run", "").strip
          sub, rest = preview_arg.split(/\s+/, 2)
          preview_arg = (sub == "preview") ? rest.to_s.strip : preview_arg
          result = fix_loop.preview(expand_or_root(preview_arg.empty? ? "." : preview_arg, root))
          return "dry-run: no changes applied\n#{format_fix_preview(result.value!)}" if result.ok?
          return "dry-run: #{result.message}"
        end
        sub, rest = arg.split(/\s+/, 2)
        case sub
        when "loop"
          result = fix_loop.start_background!(expand_or_root(rest.to_s.strip, root))
          result.ok? ? result.value! : "fix loop: #{result.message}"
        when "stop"
          result = fix_loop.stop_background!
          result.ok? ? result.value! : "fix stop: #{result.message}"
        when "preview"
          result = fix_loop.preview(expand_or_root(rest.to_s.strip, root))
          return "fix preview: #{result.message}" unless result.ok?
          format_fix_preview(result.value!)
        else
          target = expand_or_root(arg, root)
          result = fix_loop.run(target)
          result.ok? ? result.value! : "fix: #{result.message}"
        end
      end

      def format_fix_preview(data)
        total = data[:total]
        return "preview: clean — no violations" if total.zero?
        rule_lines = data[:rules].map { |r, n| "  #{r.ljust(28)} #{n}" }
        file_lines = data[:files].map { |f, n| "  #{f[0, 60].ljust(60)} #{n}" }
        ["preview: #{total} violations (no changes made)",
         "by rule:", *rule_lines,
         "top files:", *file_lines].join("\n")
      end

      # Constitutional scoreboard: per-axiom violation counts over lib/, plus a
      # rule dep-graph completeness report.
      AXIOM_SCAN_CAP = 400

      def dispatch_axioms(scanner, root, _arg)
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

      def ungraphed_rules(root)
        registered = Master::Judge::Scan::Rule.registry.map { |k| k.new.id.upcase }.uniq
        graph = (Master.load_yaml(File.join(root, "data", "rule_deps.yml")) || {})["deps"] || {}
        graphed = (graph.keys + graph.values.flat_map { |v| Array(v["after"]) }).map(&:to_s).uniq
        (registered - graphed).sort
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "command_registry.ungraphed_rules")
        []
      end

      def dispatch_scan(scanner, root, arg)
        dry_run = arg.include?("--dry-run")
        scan_arg = arg.gsub("--dry-run", "").strip
        profile, depth, rule_filter = resolve_scan_profile(scan_arg, root)
        pairs = collect_scan_pairs(scanner:, root:, arg: scan_arg, depth:)
        return pairs if pairs.is_a?(String)
        report = format_scan_results(pairs, profile, rule_filter)
        dry_run ? "dry-run: no changes applied\n#{report}" : report
      end

      def collect_scan_pairs(scanner:, root:, arg:, depth:)
        raw_arg = arg.sub(/\A(?:critical|solid|axioms|standard|deep|quick|hunt|critique|frontend)\s+/, "").strip
        target_arg = raw_arg.empty? ? nil : File.expand_path(raw_arg)
        if target_arg && File.file?(target_arg)
          [[target_arg, scanner.scan(target_arg, depth:)]]
        else
          dir = (target_arg && File.directory?(target_arg)) ? target_arg : File.join(root, "lib")
          result = scanner.scan_dir(dir, depth:, glob: "**/*", stream: true)
          result.ok? ? result.value! : "scan failed"
        end
      end

      def format_scan_results(pairs, profile, rule_filter)
        by_rule = Hash.new { |h, k| h[k] = [] }
        pairs.each do |_file, file_result|
          Result.wrap(file_result).value_or([]).each do |v|
            next if rule_filter && !rule_filter.include?(v[:rule].to_s)
            by_rule[v[:rule].to_s] << v
          end
        end
        total = by_rule.values.sum(&:size)
        header = profile ? "[profile: #{profile}] " : ""
        return "" if total.zero?
        summary = "#{header}#{total} total violations"
        lines = by_rule.sort_by { |_, vs| -vs.size }.flat_map do |rule, vs|
          ["[#{rule}] #{vs.size}"] + vs.first(3).map { |v| "  L#{v[:line]}: #{v[:message][0, VIOLATION_TRUNCATE]}" }
        end
        ([summary] + lines).join("\n")
      end

      def resolve_scan_profile(arg, root)
        groups, profiles = load_workflow_profiles(root)
        profile_name = %w[critical solid axioms].find { |p| arg.start_with?(p) }
        return [nil, :deep, nil] if profile_name.nil?
        cfg = profiles[profile_name] || {}
        rule_ids = groups[cfg["rules"].to_s]
        rule_filter = (rule_ids && cfg["rules"] != "*") ? rule_ids.map(&:to_s).to_set : nil
        [profile_name, :deep, rule_filter]
      end

      @workflow_cache = {}
      @workflow_mtime = nil

      def load_workflow_profiles(root)
        path = File.join(root, "data", "workflow.yml")
        mtime = File.mtime(path)
        if @workflow_cache[root] && @workflow_mtime == mtime
          return @workflow_cache[root]
        end
        data = Master.load_yaml(path)
        pair = [data["principle_groups"] || {}, data["scan_profiles"] || {}]
        @workflow_cache[root] = pair
        @workflow_mtime = mtime
        pair
      rescue StandardError
        [{}, {}]
      end

      def dispatch_review(council_stage:, deliberation:, root:, bus:, arg:)
        case arg
        when "on"     then council_stage.enable!; "review: enabled in pipeline"
        when "off"    then council_stage.disable!; "review: disabled in pipeline"
        when "status" then "review: #{council_stage.enabled? ? "on" : "off"} in pipeline"
        else
          target = arg.empty? ? "." : arg
          artifact = snapshot_artifact(expand_or_root(target, root))
          run_deliberation(deliberation:, artifact:, target:, bus:, formatter: :tribunal)
        end
      end

      def run_deliberation(deliberation:, artifact:, target:, bus: nil, formatter: :tribunal)
        return "deliberation: not configured" unless deliberation
        result = deliberation.review_convergent(artifact, context: target)
        return result.message if result.err?
        Judge::Council::FeedbackFormatter.format(result.value!, style: formatter, bus:)
      rescue StandardError => e
        "deliberation: #{e.message}"
      end

      def run_tribunal(deliberation:, artifact:, target:, bus: nil)
        run_deliberation(deliberation:, artifact:, target:, bus:, formatter: :tribunal)
      end

      def format_tribunal(feedback, bus = nil)
        Judge::Council::FeedbackFormatter.format(feedback, style: :tribunal, bus:)
      end

      def snapshot_artifact(abs_path)
        return "not found: #{abs_path}" unless File.exist?(abs_path)
        return File.read(abs_path).b[0, 16_000] if File.file?(abs_path)
        files = Dir.glob(File.join(abs_path, "**/*.{rb,erb,yml}")).first(40)
        files.map { |f| "--- #{f.sub(abs_path + "/", "")} ---\n#{File.read(f).b[0, 800]}" }.join("\n\n")[0, 24_000]
      end

      def dispatch_critique(deliberation, root, arg)
        return "usage: /critique <file|text>" if arg.empty?
        path = File.expand_path(arg, root)
        payload = File.exist?(path) ? File.read(path, encoding: "UTF-8") : arg
        run_deliberation(deliberation:, artifact: payload, target: "explicit /critique session", formatter: :feedback)
      end

      def deliberation_feedback(feedback)
        Judge::Council::FeedbackFormatter.format(feedback, style: :feedback)
      end

      def dispatch_model(agent:, config:, metrics:, root:, arg:)
        return list_models(root, metrics, agent) if arg == "list"
        return "model: #{agent.model}" if arg.empty?
        agent.model = arg; config.save!; "model: #{arg}"
      end

      def list_models(root, metrics, agent)
        yml_path = File.join(root, "data", "models.yml")
        return "model: #{agent.model}" unless File.exist?(yml_path)
        data = Master.load_yaml(yml_path)
        tiers = data["models"] || {}
        current = agent.model.to_s
        model_lines = tiers.flat_map { |tier, ms|
          ms.to_a.map { |mod|
            id = mod["id"].to_s
            mark = id == current ? "→ " : "  "
            "#{mark}[#{tier}] #{id}"
          }
        }
        quality_lines = metrics&.model_quality&.map { |mod, stat|
          "  #{mod}: #{stat[:calls]} calls, fail_rate=#{stat[:fail_rate]}"
        } || []
        sections = ["available models:"] + model_lines
        sections += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
        sections.join("\n")
      end

      def dispatch_why(agent, root, rule)
        return "usage: /why <law|scan_rule|anti_pattern|style.key>" if rule.empty?
        local = Trace::WhyExplainer.new(root:).explain(rule)
        return local if local
        agent.ask_once("Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
                       "give a before/after Ruby example, and state why it matters.")
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
