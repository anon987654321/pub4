# frozen_string_literal: true

require "set"
require "time"
require_relative "run_journal"
require_relative "fix_loop/committer"
require_relative "fix_loop/council_round"
require_relative "fix_loop/llm_router"
require_relative "fix_loop/scanner"
require_relative "fix_loop/file_collector"
require_relative "fix_loop/rule_order"
require_relative "fix_loop/pass_runner"
require_relative "fix_loop/convergence_config"
require_relative "fix_loop/background_runner"
require_relative "fix_loop/pass_runner_builder"
require_relative "visual_pass"
require_relative "opportunity_pass"
require_relative "rename_sweep"
require_relative "severity"
require_relative "violation"

module Master
  module Fix
    # Observe, critique, repair and observe again until the tree converges, stops
    # improving, or reaches a state MASTER may not settle on its own. A run ends
    # in one of TERMINAL_STATES and says which: "complete" for a run that merely
    # ran out of passes is the false completion this loop exists to refuse.
    class FixLoop
      include ConvergenceConfig
      include BackgroundRunner
      include PassRunnerBuilder

      # How a run is allowed to end, and every ending says which it was. DONE is
      # the only one that claims the work is finished: the tree observed clean
      # the required number of times in a row, with the ground truth agreeing.
      # PLATEAU is convergence without that proof — the same findings keep
      # coming back, or the passes ran out. HUMAN_DECISION is a safe halt when a
      # proposed fix is irreversible or spans multiple files. BLOCKED is a halt
      # outside the loop's authority, and VALIDATION_FAILED is a repair the tree refused.
      TERMINAL_STATES = %i[done plateau blocked validation_failed delivery_failed timeout human_decision failed reloading].freeze
      # A pass status that ends the run, and the state it ends in.
      PASS_ENDINGS = { clean: :done, validation_failed: :validation_failed,
                       delivery_failed: :delivery_failed, reloading: :reloading }.freeze

      IDLE_SLEEP = 300
      STARTUP_DELAY = 90
      MAX_PASSES = 15
      CLEAN_RUNS = 2
      PLATEAU_WINDOW = 3
      # Thirty minutes suits API lanes. A run whose every call goes through a
      # subscription CLI (MASTER_MODEL=claude-cli:...) spends that on one
      # council, so the run can be given more.
      RUN_BUDGET_SECONDS = Integer(ENV.fetch("MASTER_FIX_RUN_BUDGET_S", 30 * 60))
      WORKFLOW_PATH = Master.limits_path.freeze

      def initialize(rules:, agent:, scanner:, root:, axioms: nil, bus: nil, git: nil, learnings: nil,
                     rollback: nil, incremental: false, ground_truth: nil, preserve_user_intent: nil,
                     law_resolver: nil, homeostat: nil)
        @rules = rules
        @axioms = axioms
        @agent = agent
        @root = root
        @bus = bus
        @homeostat = homeostat
        @incremental = incremental
        @halted = false
        @halt_reason = nil
        @git = git || Io::GitOperations.new(root)
        @run_journal = RunJournal.new(root:, bus:)

        @file_collector = FileCollector.new(root:, bus:)
        @rule_order = RuleOrder.new(rules:, learnings:, bus:, root:)
        @pass_runner = build_pass_runner(rules:, agent:, scanner:, root:, bus:, learnings:, rollback:,
          ground_truth:, preserve_user_intent:, law_resolver:, homeostat: @homeostat)
        # Wire Ledger::Reflexion for strict self-correction per rules.yml (AK102, self-application)
        @reflexions = Trace::Ledger::Reflexion.new(event_bus: bus, root:) if bus
        @sweeps = build_sweeps(agent:, root:, bus:)
      end

      # A halt stops the runs nobody asked for, the background runner and the
      # watcher, when MASTER's own tree reads red. An operator's /fix is the
      # request to repair exactly that tree; halting it too refused every fix
      # while a single violation stood, so "fix and commit" scanned and stopped.
      def run(target = @root, max_passes: max_passes_default, budget_seconds: RUN_BUDGET_SECONDS,
              incremental: @incremental, requested: false)
        mission = nil
        return halted_result if halted? && !requested

        files = incremental ? @file_collector.collect_changed(target) : @file_collector.collect(target)
        journal = @run_journal.start_or_resume(target:, files:, max_passes:, budget_seconds:)
        run_id = journal["id"]
        budget_error = exhausted_budget(journal:, run_id:)
        return budget_error if budget_error

        mission = mission_for(target:)
        run_journaled(journal, files:, target:, max_passes:, budget_seconds:, mission:)
      rescue StandardError => e
        @bus&.publish("fix_loop:crash", error: e.message, backtrace: e.backtrace&.first(8))
        @run_journal&.crash(run_id, e.message) if defined?(run_id) && run_id
        mission&.fail!(e)
        Result.err("fix_loop: #{e.message} @ #{e.backtrace&.first(3)&.join(" | ")}", category: :unknown)
      end

      def finish_run(result, target, run_id, mission: nil)
        state = terminal_state_for(result)
        @run_journal.terminal(run_id, state, message: result.to_s)
        mission&.transition!(:verify, summary: result.to_s)
        mission_state = state == :done ? "completed" : "interrupted"
        mission&.finish!(state: mission_state, summary: result.to_s)
        @bus&.publish("fix_loop:terminal", state:, message: result.to_s)
        result
      end

      # Structural sweeps run between repair passes, with no transaction open:
      # a rename or restructure moves files the pass transactions track by path,
      # so each sweep is isolated and a kept change returns to fresh observation.
      def sweep_tree(target, run_id)
        @sweeps.flat_map do |sweep|
          sweep.run(target:, run_id:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.#{sweep.class.name.split("::").last}", event_bus: @bus)
          []
        end
      end

      def retry_delivery(transaction_id:, expected_head:)
        actual_head = @git.head
        return Result.err("delivery recovery HEAD mismatch", category: :policy) unless actual_head == expected_head

        @git.push
        ahead, = @git.ahead_behind
        return Result.err("delivery recovery left #{ahead} unpushed commit(s)", category: :infrastructure) unless ahead.zero?

        transaction = Transaction::Recovery.load_persisted(root: @root, id: transaction_id, bus: @bus)
        result = transaction.delivery.finalize!(head: actual_head)
        return result if result.err?

        Result.ok(:delivery_recovered)
      rescue StandardError => e
        Result.err("delivery recovery: #{e.message}", category: :infrastructure)
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
          skipped: @file_collector.skipped,
        )
      end

      def collect_files(target) = @file_collector.collect(target)

      def ordered_rules(violation_counts: {})
        @rule_order.ordered(violation_counts:)
      end

      def self.preamble_from_soul = RuleLoop.soul_preamble

      private

      # The look back over the tree after the repair passes: renames, then
      # restructures. Both work from the repository root.
      def build_sweeps(agent:, root:, bus:)
        repo_root = File.basename(root) == "MASTER" ? File.expand_path("..", root) : root
        [RenameSweep.new(agent:, repo_root:, bus:), RestructureSweep.new(agent:, repo_root:, bus:)]
      end

      # The run once its journal is open and a mission records it: resume what
      # an earlier process left, then the passes, then the terminal state.
      def run_journaled(journal, files:, target:, max_passes:, budget_seconds:, mission:)
        run_id = journal["id"]
        files = StreamCursor.order(@root, target, files)
        deadline = Ground::Reliability::Deadline.new(journal["remaining_seconds"].to_f)
        start_pass = @run_journal.next_pass(journal)
        @bus&.publish("fix_loop:recovered", run_id:, start_pass:, target:) if journal["resumed"]

        resumed = resume_active_transaction(journal:, run_id:, start_pass:)
        return resumed.tap { mission.fail!(resumed.message) } if resumed.err?

        result = run_passes(files:, target:, max_passes:, deadline:, budget_seconds:, start_pass: resumed.value!, run_id:)
        finish_run(result, target, run_id, mission:)
      end

      def mission_for(target:)
        checkpoint = lambda do |id:, root:, files:|
          Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints")).create(
            label: "mission-#{id}", files:,
          )
        end
        Master::Fix::Mission.new(root: @root, bus: @bus, checkpoint:).start!(
          goal: "fix #{relative_target(target)}",
          scope: target,
          model: @agent.respond_to?(:model) ? @agent.model : ENV["MASTER_MODEL"],
          effort: ENV.fetch("MASTER_EFFORT", "high"),
          plan: Ground::ActivePlan.read(@root),
        ).transition!(:plan, plan: Ground::ActivePlan.read(@root) || "fix plan: observe, critique, repair, verify")
          .transition!(:execute)
      rescue StandardError => e
        @bus&.publish("mission:error", error: e.message, phase: "start")
        raise
      end

      def relative_target(path)
        full = File.expand_path(path, @root)
        root = File.expand_path(@root)
        return path.to_s unless full == root || full.start_with?(root + File::SEPARATOR)

        full.delete_prefix(root + File::SEPARATOR)
      end

      def exhausted_budget(journal:, run_id:)
        return if journal["remaining_seconds"].to_f > 0

        result = Result.err("fix budget exhausted before resume", category: :timeout)
        @run_journal.terminal(run_id, :timeout, message: result.message)
        result
      end

      def resume_active_transaction(journal:, run_id:, start_pass:)
        active_pass = @run_journal.active_pass(journal)
        unless active_pass && Transaction::Recovery.persisted?(root: @root, id: active_pass.fetch("transaction_id"))
          return Result.ok(start_pass)
        end

        recovery = Transaction::Recovery.recover!(root: @root, id: active_pass.fetch("transaction_id"), bus: @bus)
        if recovery.err?
          @run_journal.terminal(run_id, :failed, message: recovery.message)
          return recovery
        end
        return Result.ok(start_pass) unless recovery.value!.is_a?(Hash) && recovery.value![:state] == :delivery_pending

        recover_pending_delivery(active_pass:, run_id:, commit: recovery.value!.fetch(:commit))
      end

      def recover_pending_delivery(active_pass:, run_id:, commit:)
        recovery_result = retry_delivery(transaction_id: active_pass.fetch("transaction_id"), expected_head: commit)
        if recovery_result.err?
          @run_journal.terminal(run_id, :failed, message: recovery_result.message)
          return recovery_result
        end
        @run_journal.pass_finish(run_id, active_pass.fetch("pass"), status: :committed,
                                 message: "recovered Git delivery")
        Result.ok(active_pass.fetch("pass").to_i + 1)
      end

      def terminal_state_for(result)
        return :timeout if result.err? && result.category == :timeout
        return result.value!.to_s[/\A[A-Z_]+/].to_s.downcase.to_sym if result.ok?

        :failed
      end

      # start_pass is the number of the first pass to run, 1-based like the
      # journal's next_pass; run_one_pass takes the 0-based index.
      def run_passes(files:, target:, max_passes:, deadline:, budget_seconds:, start_pass: 1, run_id:)
        state = { history: [], seen_snapshots: Set.new, recurring_violations: Hash.new(0), consecutive_clean: 0 }

        first_index = start_pass - 1
        remaining_passes = [max_passes - first_index, 0].max
        remaining_passes.times do |offset|
          i = first_index + offset
          outcome = run_one_pass(i, files:, target:, deadline:, budget_seconds:, state:, run_id:)
          return terminal(:plateau, "no further improvement after #{i + 1} pass(es)") if outcome == :break
          return outcome if outcome
        end

        # Reaching the bound is not finishing. The pass limit is a circuit
        # breaker, and a run that hit it has findings it never got to.
        terminal(:plateau, "pass limit (#{max_passes}) reached")
      end

      # Every ending carries its state, so a caller cannot read "clean after 2
      # passes" as "the tree is done" when the loop merely stopped.
      def terminal(state, message)
        raise ArgumentError, "unknown terminal state: #{state}" unless TERMINAL_STATES.include?(state)

        Result.ok("#{state.to_s.upcase}: #{message}")
      end

      def run_one_pass(i, files:, target:, deadline:, budget_seconds:, state:, run_id:)
        pass = i + 1
        transaction_id = "#{run_id}-pass-#{pass}"
        @run_journal.pass_start(run_id, pass, transaction_id:)

        @homeostat&.observe(:tool_call) # a pass is loop overhead distinct from the LLM call inside it
        if deadline.expired?
          @bus&.publish("fix_loop:timeout", pass:, budget_seconds:)
          # Err, not ok. A run that stopped because the clock ran out did not
          # finish fixing, and saying "ok" here is how the 2026-07-31 gate
          # reported a green MASTER phase whose /fix had completed exactly one
          # pass: bin/cli exited 0, bin/gate saw success, and the /scan on
          # either side of it printed the identical 110 violations.
          #
          # :timeout matches LLMDispatcher's category for the same situation, so
          # a caller that wants to treat "ran out of time" differently from
          # "genuinely failed" can, and one that does not gets the truth by
          # default. Both callers already handle err: watch_loop ignores
          # the return and through_pipeline logs "fail".
          return Result.err("wall-clock timeout (#{budget_seconds}s) after #{i} pass(es)", category: :timeout)
        end

        result = @pass_runner.run_pass(
          files:, target:, pass:, deadline: deadline.at, transaction_id:,
          history: state[:history], seen_snapshots: state[:seen_snapshots],
          recurring_violations: state[:recurring_violations],
          consecutive_clean: state[:consecutive_clean]
        )
        state[:consecutive_clean] = result.consecutive_clean
        structural = if %i[clean plateau].include?(result.status)
                       sweep_tree(target, run_id)
                     else
                       []
                     end
        if structural.any?
          state[:consecutive_clean] = 0
          files.replace(@file_collector.collect(target))
          message = "structural surgery kept #{structural.size}; re-entering repair"
          @run_journal.pass_finish(run_id, pass, status: :structural_repair, message:)
          @bus&.publish("fix_loop:structural_repair", pass:, changes: structural.size)
          Master::Trace::Dmesg.status("fix0", "pass #{pass}, #{message}")
          return nil
        end

        @run_journal.pass_finish(run_id, pass, status: result.status, message: result.message)
        ending = PASS_ENDINGS[result.status]
        return terminal(ending, result.message) if ending

        result.status == :plateau ? :break : nil
      end

      def halted_result = Result.err("BLOCKED: fix_loop halted, #{@halt_reason || "self_violation"}", category: :policy)

      def workflow_cfg
        @workflow_cfg ||= begin
          config = Master.load_yaml(WORKFLOW_PATH)
          raise "workflow config missing or unreadable: #{WORKFLOW_PATH}" unless config.is_a?(Hash)
          config
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix_loop.workflow_cfg", event_bus: @bus)
        raise "fix_loop: workflow configuration unreadable: #{e.class}: #{e.message}"
      end
    end
  end
end
