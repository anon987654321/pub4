# frozen_string_literal: true

require "set"
require "time"
require_relative "fix_loop/committer"
require_relative "fix_loop/llm_router"
require_relative "fix_loop/scanner"
require_relative "fix_loop/file_collector"
require_relative "fix_loop/rule_order"
require_relative "fix_loop/pass_runner"
require_relative "fix_loop/convergence_config"
require_relative "fix_loop/background_runner"
require_relative "severity"
require_relative "violation"

module Master
  module Fix
  # Two-tier act-react loop — architectures #1, #2, #3, #14, #15.
    class FixLoop
      include ConvergenceConfig
      include BackgroundRunner

      IDLE_SLEEP          = 300
      STARTUP_DELAY       = 90
      MAX_PASSES          = 15
      CLEAN_RUNS          = 2
      PLATEAU_WINDOW      = 3
      RUN_BUDGET_SECONDS  = 30 * 60
      WORKFLOW_PATH       = Master.limits_path.freeze

      def initialize(rules:, agent:, scanner:, root:, axioms: nil, bus: nil, git: nil, learnings: nil,
                     rollback: nil, incremental: false, ground_truth: nil, preserve_user_intent: nil,
                     law_resolver: nil)
        @rules       = rules
        @axioms      = axioms
        @root        = root
        @bus         = bus
        @incremental = incremental
        @halted      = false
        @halt_reason = nil
        @git         = git || Io::GitOperations.new(root)

        @file_collector = FileCollector.new(root:, bus:)
        @rule_order     = RuleOrder.new(rules:, learnings:, bus:, root:)
        @pass_runner    = build_pass_runner(rules:, agent:, scanner:, root:, bus:, learnings:, rollback:,
          ground_truth:, preserve_user_intent:, law_resolver:)
        # Wire ReflexionLedger for strict self-correction per rules.yml (AK102, self-application)
        @reflexions = Trace::ReflexionLedger.new(event_bus: bus, root:) if bus
      end

      def run(target = @root, max_passes: max_passes_default, budget_seconds: RUN_BUDGET_SECONDS, incremental: @incremental)
        return halted_result if halted?

        files    = incremental ? @file_collector.collect_changed(target) : @file_collector.collect(target)
        deadline = Time.now + budget_seconds

        run_passes(files:, target:, max_passes:, deadline:, budget_seconds:)
      rescue StandardError => e
        @bus&.publish("fix_loop:crash", error: e.message, backtrace: e.backtrace&.first(8))
        Result.err("fix_loop: #{e.message} @ #{e.backtrace&.first(3)&.join(" | ")}", category: :unknown)
      end

      def preview(target = @root)
        files = @file_collector.collect(target)
        violations = @pass_runner.violations(files)
        by_rule = violations.group_by { |v| v[:rule].to_s }.transform_values(&:size)
        by_file = violations.group_by { |v| v[:file].to_s }.transform_values(&:size)
        Result.ok(
          total: violations.size,
          rules: by_rule.sort_by { |_, n| -n }.first(10).to_h,
          files: by_file.sort_by { |_, n| -n }.first(10).to_h,
        )
      end

      def collect_files(target) = @file_collector.collect(target)

      def ordered_rules(violation_counts: {})
        @rule_order.ordered(violation_counts:)
      end

      def self.preamble_from_soul = RuleLoop.soul_preamble

      private

      def build_pass_runner(rules:, agent:, scanner:, root:, bus:, learnings:, rollback:,
        ground_truth:, preserve_user_intent:, law_resolver:)
        committer    = Committer.new(git: @git, bus:, root:,
                                     ground_truth:, preserve_user_intent:)
        conflict_resolver = ConflictResolver.new(root:, bus:, law_resolver:)
        loop_scanner = Scanner.new(scanner:, root:, bus:, conflict_resolver:)
        llm_router   = LlmRouter.new(agent)
        preamble     = self.class.preamble_from_soul

        PassRunner.new(
          bus:, committer:, loop_scanner:, llm_router:, rollback:, root:,
          rules:, agent:, scanner:, learnings:, preamble:,
          clean_runs_required:,
          plateau_window:,
          ground_truth:
        )
      end

      def run_passes(files:, target:, max_passes:, deadline:, budget_seconds:)
        state = { history: [], seen_snapshots: Set.new, recurring_violations: Hash.new(0), consecutive_clean: 0 }

        max_passes.times do |i|
          outcome = run_one_pass(i, files:, target:, deadline:, budget_seconds:, state:)
          break if outcome == :break
          return outcome if outcome
        end

        Result.ok("plateau or max passes reached")
      end

      def run_one_pass(i, files:, target:, deadline:, budget_seconds:, state:)
        pass = i + 1
        if Time.now >= deadline
          @bus&.publish("fix_loop:timeout", pass:, budget_seconds:)
          return Result.ok("wall-clock timeout (#{budget_seconds}s) after #{i} pass(es)")
        end

        result = @pass_runner.run_pass(
          files:, target:, pass:, deadline:,
          history: state[:history], seen_snapshots: state[:seen_snapshots],
          recurring_violations: state[:recurring_violations],
          consecutive_clean: state[:consecutive_clean]
        )
        state[:consecutive_clean] = result.consecutive_clean
        return Result.ok(result.message) if result.status == :clean

        result.status == :plateau ? :break : nil
      end

      def halted_result = Result.err("fix_loop halted: #{@halt_reason || "self_violation"}", category: :policy)

      def workflow_cfg
        @workflow_cfg ||= Master.load_yaml(WORKFLOW_PATH) || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix_loop.workflow_cfg", event_bus: @bus)
        {}
      end
    end
  end
end
