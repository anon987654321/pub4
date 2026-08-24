# frozen_string_literal: true

require "json"
require "open3"
require "set"
require "time"
require_relative "../../trace/log/event"
require_relative "formatter"
require_relative "../fix_preview_report"
require_relative "../resync_service"
require_relative "../scan_report"
require_relative "../scan_request"
require_relative "../scan_live"
require_relative "../../review/review_crew"
require_relative "../../review/scan/cross_file_analysis"
require_relative "../../review/scan/edge_case_stub_generator"
require_relative "../../review/scan/mechanical_autofix"
require_relative "../tribunal_feedback"
require_relative "work_commands_extra"
require_relative "work_commands_status"

module Master
  module CLI
    module CommandRegistry
      module_function

      VIOLATION_TRUNCATE = Master::VIOLATION_TRUNCATE
      SNAPSHOT_FILE_BYTES = 8_000
      SNAPSHOT_DIR_FILE_BYTES = 1_200
      SNAPSHOT_DIR_TOTAL_BYTES = 32_000
      SNAPSHOT_DIR_FILE_LIMIT = 40
      SCAN_RULE_GROUP_LIMIT = 10

      def work_command_deps(ai:, root:, infra:)
        { root: }.merge(ai_command_deps(ai:, root:, infra:)).merge(infra_command_deps(infra:))
      end

      def ai_command_deps(ai:, root:, infra:)
        {
          scanner: ai[:scanner],
          fix_loop: ai[:fix_loop],
          ecology: ai[:ecology],
          deliberation: ai[:deliberation],
          council_stage: ai[:council_stage],
          agent: ai[:agent],
          code_index: ai[:code_index],
          reference_graph: ai[:reference_graph],
          propose_tree: ai[:propose_tree],
          review_crew: Review::ReviewCrew.new(agent: ai[:agent], event_bus: infra[:bus], root:,
                                             code_index: ai[:code_index], reference_graph: ai[:reference_graph]),
          git: ai.fetch(:git) { Io::GitOperations.new(File.expand_path("..", root)) },
        }
      end

      def infra_command_deps(infra:)
        {
          session: infra[:session],
          bus: infra[:bus],
          config: infra[:config],
          metrics: infra[:metrics],
          learnings: infra[:learnings],
          trace: infra[:trace],
        }
      end

      def dispatch_mode(root:, ctx: nil)
        arg = arg_for(ctx).to_s.strip
        posture = Master::Ground::ModePosture.new(root:)
        return posture.line if arg.empty? || arg == "status"
        return mode_list(posture) if arg == "list"

        mode = arg.split(/\s+/).first
        c = posture.set!(mode)
        "#{posture.line} — #{c[:description]}"
      rescue ArgumentError => e
        "mode: #{e.message}"
      end

      # Every posture rendered through the same formatter as the status line,
      # so what `/mode list` shows and what `/mode` reports cannot drift apart.
      # The active one is marked; the rest are what you would switch into.
      def mode_list(posture)
        active = posture.current[:name]
        Master::Ground::ModePosture::MODES.map do |name|
          spec = posture.describe(name)
          "#{name == active ? '*' : ' '} #{posture.line(spec)} — #{spec[:description]}"
        end.join("\n")
      end

      def dispatch_map(root:, ctx: nil)
        arg = arg_for(ctx).to_s.strip
        map = Master::Ground::Map::Principle.load(root:)
        case arg
        when "", "status" then map.summary_line
        when "gaps" then map_gaps_report(map)
        when "aesthetic", "ui" then map_aesthetic_report(map)
        when "covered" then map_covered_report(map)
        when "integrity" then map_integrity_report(map, root:)
        when "provenance" then map_provenance_report(map)
        else map_principle_detail(map, arg)
        end
      end

      def map_gaps_report(map)
        map.gaps.first(40).map { |id, e| "#{id.ljust(28)} #{e.severity.ljust(8)} #{e.operation || "-"}  #{e.meaning}" }.join("\n")
      end

      def map_aesthetic_report(map)
        map.aesthetic.first(60).map { |id, e| "#{id.ljust(28)} #{e.status.ljust(8)} rules=#{e.rule_ids.join(",")}" }.join("\n")
      end

      def map_covered_report(map)
        map.covered.first(40).map { |id, e| "#{id.ljust(28)} → #{e.rule_ids.join(", ")}" }.join("\n")
      end

      def map_integrity_report(map, root:)
        registered = Master::Review::Scan::Rule.registry.filter_map { |k| Master::Review::Scan::RuleFactory.registry_id(k, root:)&.upcase }
        hits = map.integrity(registered_rule_ids: registered)
        hits.empty? ? "principle_map integrity: clean" : hits.join("\n")
      end

      # Advisory, not enforced -- see Map::Principle#provenance_gaps for why
      # this stays out of SelfTest's gating path.
      def map_provenance_report(map)
        gaps = map.provenance_gaps
        return "principle_map provenance: all #{map.principles.size} entries attributed" if gaps.empty?

        header = "principle_map provenance: #{gaps.size}/#{map.principles.size} entries missing source:"
        ([header] + gaps.first(40).map { |entry| "  #{entry.id}" }).join("\n")
      end

      def map_principle_detail(map, arg)
        entry = map[arg]
        return "map: unknown principle #{arg.inspect} (try /map gaps|aesthetic|covered|integrity)" unless entry

        [
          entry.id,
          "status=#{entry.status} severity=#{entry.severity} conf=#{entry.confidence}",
          "detects=#{entry.detects} operation=#{entry.operation}",
          "rules=#{entry.rule_ids.join(", ")}",
          "tags=#{entry.tags.join(", ")}",
          entry.meaning,
        ].join("\n")
      end

      def dispatch_core(root:, ctx: nil)
        smoke = File.join(root, "core", "spec", "core_smoke.rb")
        return "core: smoke script missing at #{smoke}" unless File.file?(smoke)

        out, status = Master::Io::Exec.capture2e(Gem.ruby, smoke, chdir: root)
        status.success? ? out.lines.last(5).join : "core smoke failed:\n#{out}"
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
        case arg
        when "", "list"
          Master::Review::Scan::Rule.registry.map do |rule_class|
            rule = rule_class.new
            severity = rule.respond_to?(:severity) ? rule.severity : "?"
            "#{rule.id.to_s.ljust(28)} #{severity.to_s.ljust(8)} #{rule_class.name}"
          end.sort.join("\n")
        when "status", "audit"
          audit = Master::Review::Scan::RuleRegistryAudit.new.call
          ([audit.lines.join("\n")] + audit.lexical_unwired.first(12).map { |id| "  unwired: #{id}" }).join("\n")
        when "deps"
          gaps = Master::Review::Scan::RuleRegistryAudit.new.ungraphed_rule_ids
          "rule_deps gaps: #{gaps.size}\n#{gaps.first(20).join("\n")}"
        else
          "usage: /rules list|status|deps"
        end
      rescue StandardError => e
        "rules: #{e.message}"
      end

      def dispatch_edge_cases(root:, ctx: nil)
        arg = arg_for(ctx)
        return "usage: /edge-cases <ruby-file>" if arg.empty?

        Master::Review::Scan::EdgeCaseStubGenerator.new(root:).call(arg).then do |result|
          result.ok? ? result.value! : result.message
        end
      end

      def dispatch_analyze_self(learnings:, ctx: nil)
        return "analyze-self: feedback ledger unavailable" unless learnings&.respond_to?(:opportunities)

        rows = learnings.opportunities
        return "analyze-self: no recurring optimization opportunities" if rows.empty?

        rows.map do |row|
          case row[:category]
          when :high_failure
            "high_failure #{row[:dimension]} fail_rate=#{row[:fail_rate]} total=#{row[:total]}"
          when :repeated_correction
            "repeated_correction #{row[:dimension]} count=#{row[:count]}"
          when :provider_errors
            "provider_errors #{row[:dimension]} count=#{row[:count]}"
          else
            "#{row[:category]} #{row[:dimension]}"
          end
        end.join("\n")
      end

      def ungraphed_rules(root)
        rule_classes = Master::Review::Scan::Rule.registry
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
        ScanReport.new(pairs:, profile:, rule_filter:,
                       severity_filter:, dry_run:).render
      end

      def resolve_scan_profile(arg, root)
        ScanRequest.resolve_scan_profile(arg, root)
      end

      def dispatch_scan(scanner:, root:, ctx: nil)
        ScanLive.ensure_sync!
        arg, dry_run, no_autofix, clean_arg, do_autofix = parse_scan_args(ctx)

        ScanLive.with_interrupt_dump(root:) do |holder|
          scan_pass(scanner:, root:, clean_arg:, dry_run:, no_autofix:, do_autofix:, holder:)
        end
      end

      def parse_scan_args(ctx)
        arg = arg_for(ctx)
        dry_run = dry_run_arg?(arg)
        no_autofix = no_autofix_arg?(arg)
        clean_arg = strip_scan_flags(arg)
        do_autofix = !dry_run && !no_autofix && Master::Review::Scan::MechanicalAutofix.enabled?
        [arg, dry_run, no_autofix, clean_arg, do_autofix]
      end

      def scan_pass(scanner:, root:, clean_arg:, dry_run:, no_autofix:, do_autofix:, holder:)
        ScanLive.banner(target: clean_arg.empty? ? root : clean_arg, profile: nil, dry_run:, autofix: do_autofix)

        request = ScanRequest.new(scanner:, root:, arg: clean_arg).call
        return request.pairs if request.pairs.is_a?(String)

        pairs, profile, rule_filter, severity_filter = request.pairs, request.profile, request.rule_filter, request.severity_filter
        pass1_total = run_scan_pass1(pairs:, profile:, rule_filter:, severity_filter:, dry_run:, root:, holder:)

        pairs, autofixes = run_scan_autofix_phase(
          scanner:, root:, clean_arg:, pairs:, do_autofix:, dry_run:, no_autofix:,
        )

        text = render_final_scan_report(
          pairs:, profile:, rule_filter:, severity_filter:, dry_run:, autofixes:, do_autofix:, pass1_total:,
        )
        holder[:text] = text
        ScanLive.snapshot!(text, root:, note: "final")
        text
      end

      def run_scan_pass1(pairs:, profile:, rule_filter:, severity_filter:, dry_run:, root:, holder:)
        pass1 = ScanReport.new(
          pairs:, profile:, rule_filter:, severity_filter:,
          dry_run:, phase: "pass1"
        )
        ScanLive.emit("pass1 #{pass1.brief}")
        holder[:text] = pass1.render
        ScanLive.snapshot!(holder[:text], root:, note: "pass1 before autofix")
        pass1.total_count
      end

      def run_scan_autofix_phase(scanner:, root:, clean_arg:, pairs:, do_autofix:, dry_run:, no_autofix:)
        autofixes = []
        if pairs.any? && do_autofix
          ScanLive.emit("autofix applying on auto_fix findings…")
          autofixes = apply_scan_autofixes(scanner:, root:, pairs:)
          if autofixes.any?
            transforms = autofixes.flat_map { |a| Array(a[:transforms]) }.uniq.first(8).join(" ")
            ScanLive.emit("autofixed files=#{autofixes.size} transforms=#{transforms}")
            ScanLive.emit("pass2 re-scan after autofix…")
            rescanned = ScanRequest.new(scanner:, root:, arg: clean_arg).call
            pairs = rescanned.pairs unless rescanned.pairs.is_a?(String)
          else
            ScanLive.emit("autofix none applied (no auto_fix hits or no transforms)")
          end
        elsif dry_run
          ScanLive.emit("autofix skipped dry_run=yes")
        elsif no_autofix
          ScanLive.emit("autofix skipped --no-autofix")
        end
        [pairs, autofixes]
      end

      def render_final_scan_report(pairs:, profile:, rule_filter:, severity_filter:, dry_run:, autofixes:, do_autofix:, pass1_total:)
        final = ScanReport.new(
          pairs:,
          profile:,
          rule_filter:,
          severity_filter:,
          dry_run:,
          autofixes:,
          phase: do_autofix && autofixes.any? ? "pass2" : "final",
          prior_total: do_autofix ? pass1_total : nil,
        )
        text = pairs.empty? && autofixes.empty? ? clean_scan_line(dry_run:, autofixes:) : final.render
        ScanLive.emit("done #{final.brief}")
        text
      end

      def apply_scan_autofixes(scanner:, root:, pairs:)
        Master::Review::Scan::MechanicalAutofix.new(scanner:, root:).apply(pairs).map do |applied|
          { path: applied.path, transforms: applied.transforms }
        end
      end

      def clean_scan_line(dry_run:, autofixes: [])
        ScanReport.new(
          pairs: [],
          profile: nil,
          rule_filter: nil,
          dry_run:,
          autofixes:,
          phase: "final",
        ).render
      end

      def dry_run_arg?(arg)
        arg.to_s.split(/\s+/).include?("--dry-run")
      end

      def no_autofix_arg?(arg)
        arg.to_s.split(/\s+/).include?("--no-autofix")
      end

      def strip_scan_flags(arg)
        arg.to_s.split(/\s+/).reject { |part| part == "--dry-run" || part == "--no-autofix" }.join(" ")
      end

      def strip_dry_run(arg)
        strip_scan_flags(arg)
      end

      def dispatch_process(ctx: nil)
        JSON.pretty_generate(process: Master::Ops::ProcessBudget.status, loop_slot: Master::Ops::LoopSlot.status)
      end

      def dispatch_propose_tree(propose_tree, ctx: nil)
        propose_tree&.call || "propose-tree: not wired"
      end

      # /replay, formerly work_commands_replay.rb.

      def dispatch_replay(root:, trace: nil, ctx: nil)
        Trace::ReplayReader.new(root:, recorder: trace).render(arg: arg_for(ctx))
      rescue StandardError => e
        "replay: #{e.message}"
      end

      # /graph, formerly work_commands_graph.rb.

      def dispatch_graph(root:, code_index:, reference_graph:, ctx: nil)
        arg = arg_for(ctx)
        return "graph: usage: /graph <file>" if arg.empty?

        abs = expand_or_root(arg, root)
        return "graph: not found: #{arg}" unless File.file?(abs)

        data = gather_graph_data(abs, root:, code_index:, reference_graph:)
        render_graph_lines(abs.delete_prefix("#{root}/"), data).join("\n")
      rescue StandardError => e
        "graph: #{e.message}"
      end

      def gather_graph_data(abs, root:, code_index:, reference_graph:)
        reference_graph.build if reference_graph&.nodes&.empty?
        radius = reference_graph.blast_radius(abs)
        neighbors = Review::GraphRetriever.new(reference_graph:, root:)
                                           .neighbors([abs], hops: 2, limit: 10)
        symbols = code_index ? code_index.symbols_in(abs) : []
        { radius:, neighbors:, symbols: }
      end

      def render_graph_lines(rel, data)
        radius, neighbors, symbols = data[:radius], data[:neighbors], data[:symbols]
        lines = ["graph #{rel}", "  inbound (#{radius[:inbound].size}): #{radius[:inbound].first(6).join(", ")}"]
        lines << "  outbound (#{radius[:outbound].size}): #{radius[:outbound].first(6).join(", ")}"
        lines << "  neighbors (#{neighbors.size}): #{neighbors.join(", ")}" if neighbors.any?
        symbol_line = symbols.first(8).map { |sym| "#{sym.fqn}:#{sym.line}" }.join(", ")
        lines << "  symbols (#{symbols.size}): #{symbol_line}" unless symbols.empty?
        lines
      end
    end
  end
end
