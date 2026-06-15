# frozen_string_literal: true

require "set"
require "time"
require_relative "fix_loop/committer"
require_relative "fix_loop/llm_router"
require_relative "fix_loop/scanner"
require_relative "fix_loop/file_collector"
require_relative "fix_loop/rule_order"
require_relative "fix_loop/pass_runner"
require_relative "severity"
require_relative "violation"

module Master
  module Loop
  # Two-tier act-react loop — architectures #1, #2, #3, #14, #15.
    class FixLoop
      IDLE_SLEEP          = 300
      STARTUP_DELAY       = 90
      MAX_PASSES          = 15
      CLEAN_RUNS          = 2
      PLATEAU_WINDOW      = 3
      RUN_BUDGET_SECONDS  = 30 * 60
      WORKFLOW_PATH       = File.join(Master::ROOT, "data", "workflow.yml").freeze

      def initialize(rules:, agent:, scanner:, root:, axioms: nil, bus: nil, git: nil, learnings: nil, rollback: nil, incremental: false)
        @rules       = rules
        @axioms      = axioms
        @root        = root
        @bus         = bus
        @incremental = incremental
        @halted      = false
        @halt_reason = nil
        @git         = git || Reach::GitOperations.new(root)

        committer    = Committer.new(git: @git, bus: bus, root: root)
        loop_scanner = Scanner.new(scanner: scanner, root: root, bus: bus)
        llm_router   = LlmRouter.new(agent)
        preamble     = self.class.preamble_from_soul

        @file_collector = FileCollector.new(root: root, bus: bus)
        @pass_runner    = PassRunner.new(
          bus:, committer:, loop_scanner:, llm_router:, rollback:, root:,
          rules:, agent:, scanner:, learnings:, preamble:,
          clean_runs_required: clean_runs_required,
          plateau_window:      plateau_window
        )
        # Wire ReflexionLedger for strict self-correction per rules.yml (AK102, self-application)
        @reflexions = Trace::ReflexionLedger.new(event_bus: bus, root: root) if bus
      end

      def convergence_cfg = @convergence ||= (@axioms&.thresholds&.[]("convergence") || {})

      def max_passes_default     = convergence_cfg["max_iterations"]                          || MAX_PASSES
      def clean_runs_required    = convergence_cfg["consecutive_clean_runs_required"]          || CLEAN_RUNS
      def plateau_window         = convergence_cfg["stagnant_threshold"]                       || PLATEAU_WINDOW
      def max_cycles_default     = workflow_cfg.dig("autoloop", "max_cycles")                 || max_passes_default
      def startup_delay_default  = workflow_cfg.dig("autoloop", "startup_delay")              || STARTUP_DELAY
      def idle_sleep_default     = workflow_cfg.dig("autoloop", "idle_sleep")                 || IDLE_SLEEP

      def run(target = @root, max_passes: max_passes_default, budget_seconds: RUN_BUDGET_SECONDS, incremental: @incremental)
        return halted_result if halted?

        files            = incremental ? @file_collector.collect_changed(target) : @file_collector.collect(target)
        history          = []
        seen_snapshots   = Set.new
        recurring_violations = Hash.new(0)
        consecutive_clean = 0
        deadline         = Time.now + budget_seconds

        max_passes.times do |i|
          pass = i + 1
          if Time.now >= deadline
            @bus&.publish("fix_loop:timeout", pass:, budget_seconds:)
            return Result.ok("wall-clock timeout (#{budget_seconds}s) after #{i} pass(es)")
          end

          result = @pass_runner.run_pass(
            files: files, target: target, pass: pass, deadline: deadline,
            history: history, seen_snapshots: seen_snapshots,
            recurring_violations: recurring_violations,
            consecutive_clean: consecutive_clean,
            reflexions: @reflexions&.recent(5) || []  # Inject recent self-critiques for rule violations
          )
          consecutive_clean = result.consecutive_clean
          return Result.ok(result.message) if result.status == :clean
          break if result.status == :plateau
        end

        Result.ok("plateau or max passes reached")
      rescue StandardError => e
        @bus&.publish("fix_loop:crash", error: e.message, backtrace: e.backtrace&.first(8))
        Result.err("fix_loop: #{e.message} @ #{e.backtrace&.first(3)&.join(" | ")}", category: :unknown)
      end

      def run_forever(target = @root, max_cycles: max_cycles_default, startup_delay: startup_delay_default,
                      idle_sleep: idle_sleep_default, cooldown_sleep: idle_sleep_default)
        sleep startup_delay
        cycles = 0
        while cycles < max_cycles
          break if halted?
          cycles += 1
          begin
            run(target)
            break if halted?
            @bus&.publish("fix_loop:idle", sleep: idle_sleep, cycle: cycles, max_cycles:)
            sleep idle_sleep
          rescue StandardError => e
            @bus&.publish("fix_loop:error", error: e.message, cycle: cycles, max_cycles:)
            sleep cooldown_sleep
          end
        end
        @bus&.publish("fix_loop:max_cycles", cycles:, max_cycles:) unless halted?
      end

      def start_background!(target = @root)
        return Result.err("fix_loop already running") if @bg_thread&.alive?
        @halted = false
        @halt_reason = nil
        @bg_thread = Thread.new { run_forever(target) }
        @bg_thread.abort_on_exception = false
        @bus&.publish("fix_loop:background_start", target:)
        Result.ok("fix_loop background started")
      end

      def stop_background!
        return Result.err("fix_loop not running") unless @bg_thread&.alive?
        @bg_thread.kill
        @bg_thread = nil
        @bus&.publish("fix_loop:background_stop")
        Result.ok("fix_loop background stopped")
      end

      def background_alive? = @bg_thread&.alive? || false

      def halt!(reason: "self_violation")
        @halted = true
        @halt_reason = reason
        @bg_thread&.kill if @bg_thread&.alive?
        @bg_thread = nil
        @bus&.publish("fix_loop:halt", reason:)
        Result.ok("fix_loop halted: #{reason}")
      end

      def halted? = @halted

      def preview(target = @root)
        files = @file_collector.collect(target)
        violations = @pass_runner.violations(files)
        by_rule = violations.group_by { |v| v[:rule].to_s }.transform_values(&:size)
        by_file = violations.group_by { |v| v[:file].to_s }.transform_values(&:size)
        Result.ok(
          total: violations.size,
          rules: by_rule.sort_by { |_, n| -n }.first(10).to_h,
          files: by_file.sort_by { |_, n| -n }.first(10).to_h
        )
      end

      def self.preamble_from_soul
        path  = File.join(Master::ROOT, "data", "soul.yml")
        mtime = File.mtime(path).to_i
        return @preamble_cache[:value] if @preamble_cache && @preamble_cache[:mtime] == mtime

        soul   = Master.load_yaml(path)
        abs    = soul.fetch("absolute", {})
        golden = abs["golden_rule"] || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        lines  = ["Golden rule: #{golden}",
                  "Minimum change that eliminates the violation. Do not touch unrelated code."]
        abs.fetch("code_rules",      {}).each { |k, v| lines << "- #{k}: #{v}" }
        abs.fetch("aesthetic_rules", {}).each { |k, v| lines << "- #{k}: #{v}" }
        @preamble_cache = { mtime:, value: lines.join("\n") }
        @preamble_cache[:value]
      rescue StandardError
        "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
      end

      private

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
