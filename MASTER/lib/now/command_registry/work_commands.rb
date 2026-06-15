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
require_relative "../../judge/scan/cross_file_analysis"
require_relative "../../judge/scan/edge_case_stub_generator"
require_relative "../tribunal_feedback"
require_relative "work_commands_extra"

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
          "scan" => command(:dispatch_scan, scanner, root),
          "self" => command(:dispatch_self, scanner, root, bus),
          "fix" => command(:dispatch_fix, fix_loop, root, scanner),
          "status" => command(:dispatch_status, root, fix_loop, bus, git),
          "resync" => command(:dispatch_resync, root, fix_loop, git),
          "tail" => command(:dispatch_tail, root),
          "review" => command(:dispatch_review, council_stage, deliberation, root, bus, review_crew),
          "critique" => command(:dispatch_critique, deliberation, root),
          "triad" => command(:dispatch_triad, scanner, fix_loop, council_stage, deliberation, root, bus, review_crew),
          "model" => command(:dispatch_model, agent, config, metrics, root),
          "why" => command(:dispatch_why, agent, root),
          "axioms" => command(:dispatch_axioms, scanner, root),
          "rules" => command(:dispatch_rules),
          "edge-cases" => command(:dispatch_edge_cases, root),
          "topic" => command(:dispatch_topic, session),
          "process" => command(:dispatch_process),
          "propose-tree" => command(:dispatch_propose_tree, propose_tree),
          "ecology" => command(:dispatch_ecology, ecology)
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
      def dispatch_resync(root:, fix_loop:, git:, ctx: nil)
        ResyncService.new(root:, fix_loop:, git:).call(dry_run: arg_for(ctx).include?("--dry-run"))
      end

      # /tail [N] [pattern] — last N events matching pattern. Default N=20.
      def dispatch_tail(root:, ctx: nil)
        arg = arg_for(ctx)
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

      def dispatch_fix(fix_loop:, root:, scanner: nil, ctx: nil, arg: nil)
        arg = arg || arg_for(ctx)
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
          prescan = anti_sprawl_prescan(scanner:, target:, root:)
          result = fix_loop.run(target)
          output = result.ok? ? result.value! : "fix: #{result.message}"
          [prescan, output].reject(&:empty?).join("\n")
        end
      end

      def anti_sprawl_prescan(scanner:, target:, root:)
        paths = prescan_paths(target)
        return "" if paths.empty?

        pairs = Master::Judge::Scan::CrossFileAnalysis.new(root:).call(paths)
        findings = pairs.flat_map { |_path, result| Result.wrap(result).value_or([]) }
        return "prescan: clean. Moving on." if findings.empty?

        lines = ["prescan: #{findings.size} cross-file risk(s) before fix"]
        findings.first(8).each { |finding| lines << "  #{finding[:rule]}: #{finding[:message]}" }
        lines.join("\n")
      rescue StandardError => e
        scanner&.instance_variable_get(:@bus)&.publish("fix:prescan_error", path: target, error: e.message)
        "prescan: unavailable (#{e.class})"
      end

      def prescan_paths(target)
        path = target.to_s.empty? ? "." : target
        return [path] if File.file?(path)
        return [] unless File.directory?(path)

        Dir.glob(File.join(path, Master::Judge::Scan::Scanner::SCAN_GLOB)).select { |entry| File.file?(entry) }
      end

      # Constitutional scoreboard: per-axiom violation counts over lib/, plus a
      # rule dep-graph completeness report.
      AXIOM_SCAN_CAP = 400

      def dispatch_axioms(scanner:, root:, ctx: nil)
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

      def dispatch_rules(ctx: nil)
        arg = arg_for(ctx)
        return "usage: /rules list" unless arg.empty? || arg == "list"

        Master::Judge::Scan::Rule.registry.map do |rule_class|
          rule = rule_class.new
          severity = rule.respond_to?(:severity) ? rule.severity : "?"
          "#{rule.id.to_s.ljust(28)} #{severity.to_s.ljust(8)} #{rule_class.name}"
        end.sort.join("\n")
      rescue StandardError => e
        "rules: #{e.message}"
      end

      def dispatch_edge_cases(root:, ctx: nil)
        arg = arg_for(ctx)
        return "usage: /edge-cases <ruby-file>" if arg.empty?

        Master::Judge::Scan::EdgeCaseStubGenerator.new(root:).call(arg).then do |result|
          result.ok? ? result.value! : result.message
        end
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

      def format_scan_results(pairs:, profile:, rule_filter:, severity_filter: nil, dry_run: false)
        ScanReport.new(pairs: pairs, profile: profile, rule_filter: rule_filter,
                       severity_filter: severity_filter, dry_run: dry_run).render
      end

      def resolve_scan_profile(arg, root)
        ScanRequest.resolve_scan_profile(arg, root)
      end

      def dispatch_scan(scanner:, root:, ctx: nil)
        arg = arg_for(ctx)
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

      def dispatch_process(ctx: nil)
        JSON.pretty_generate(process: Master::Ops::ProcessBudget.status, loop_slot: Master::Ops::LoopSlot.status)
      end

      def dispatch_propose_tree(propose_tree, ctx: nil)
        propose_tree&.call || "propose-tree: not wired"
      end
    end
  end
end
