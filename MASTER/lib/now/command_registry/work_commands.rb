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
require_relative "work_commands_status"

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
        learnings = infra[:learnings]
        git = ai[:git] || Reach::GitOperations.new(File.expand_path("..", root))
        {
          "scan" => command(:dispatch_scan, scanner, root),
          "self" => command(:dispatch_self, scanner, root, bus),
          "kernel" => command(:dispatch_kernel, root),
          "fix" => command(:dispatch_fix, fix_loop, root, scanner),
          "status" => command(:dispatch_status, root, fix_loop, bus, git),
          "resync" => command(:dispatch_resync, root, fix_loop, git),
          "tail" => command(:dispatch_tail, root),
          "review" => command(:dispatch_review, council_stage, deliberation, root, bus, review_crew),
          "critique" => command(:dispatch_critique, deliberation, root),
          "workflow" => command(:dispatch_workflow, scanner, fix_loop, deliberation, root, bus),
          "triad" => command(:dispatch_triad, scanner, fix_loop, deliberation, root, bus),
          "model" => command(:dispatch_model, agent, config, metrics, root),
          "why" => command(:dispatch_why, agent, root),
          "axioms" => command(:dispatch_axioms, scanner, root),
          "rules" => command(:dispatch_rules),
          "edge-cases" => command(:dispatch_edge_cases, root),
          "analyze-self" => command(:dispatch_analyze_self, learnings),
          "topic" => command(:dispatch_topic, session),
          "process" => command(:dispatch_process),
          "propose-tree" => command(:dispatch_propose_tree, propose_tree),
          "ecology" => command(:dispatch_ecology, ecology)
        }
      end

      def dispatch_self(scanner:, root:, bus:, ctx: nil)
        result = Master::Judge::Scan::SelfScan.new(scanner: scanner, root: root, event_bus: bus).call(stream: true, autofix: true)
        return result.message unless result.ok?

        result.value!.line
      end

      def dispatch_kernel(root:, ctx: nil)
        smoke = File.join(root, "kernel", "spec", "kernel_smoke.rb")
        return "kernel: smoke script missing at #{smoke}" unless File.file?(smoke)

        out, status = Open3.capture2e(Gem.ruby, smoke, chdir: root)
        status.success? ? out.lines.last(5).join : "kernel smoke failed:\n#{out}"
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

        Master::Judge::Scan::EdgeCaseStubGenerator.new(root: root).call(arg).then do |result|
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
        request = ScanRequest.new(scanner: scanner, root: root, arg: strip_dry_run(arg)).call
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
