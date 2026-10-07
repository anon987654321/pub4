# frozen_string_literal: true

require "set"
require "time"
require_relative "run_journal"
require_relative "reachability"
require_relative "fix_loop/committer"
require_relative "fix_loop/council_round"
require_relative "fix_loop/llm_router"
require_relative "fix_loop/file_collector"
require_relative "fix_loop/law_order"
require_relative "fix_loop/pass_runner"
require_relative "fix_loop/convergence_config"
require_relative "fix_loop/background_runner"
require_relative "fix_loop/pass_runner_builder"
require_relative "visual_pass"
require_relative "opportunity_pass"
require_relative "rename_sweep"
require_relative "severity"
require_relative "violation"
require_relative "wishlist"
require_relative "protocol"
require_relative "transformation_plan"
require_relative "convergence_discipline"

module Master
  module Fix
    # Observe, critique, repair and observe again until the tree converges, stops
    # improving, or reaches a state MASTER may not settle on its own. A run ends
    # in one of TERMINAL_STATES and says which: "complete" for a run that merely
    # ran out of passes is the false completion this loop exists to refuse.
    class FixLoop
      attr_reader :homeostat

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
      TERMINAL_STATES = %i[done plateau crash skip blocked validation_failed delivery_failed timeout human_decision failed reloading].freeze
      # A pass status that ends the run, and the state it ends in.
      PASS_ENDINGS = { clean: :done, validation_failed: :validation_failed,
                       delivery_failed: :delivery_failed, reloading: :reloading }.freeze

      MAX_PASSES = 15
      ADAPTIVE_PASS_CHUNK = Integer(ENV.fetch("MASTER_FIX_ADAPTIVE_PASS_CHUNK", 3))
      ABSOLUTE_MAX_PASSES = Integer(ENV.fetch("MASTER_FIX_ABSOLUTE_MAX_PASSES", 60))
      CLEAN_RUNS = 2
      PLATEAU_WINDOW = 3
      WISHLIST_MAX_ROUNDS = 3
      WISHLIST_MAX_PASSES = 3
      WISHLIST_MIN_REMAINING_SECONDS = 60
      # Thirty minutes suits API lanes. A run whose every call goes through a
      # subscription CLI (MASTER_MODEL=claude-cli:...) spends that on one
      # council, so the run can be given more.
      RUN_BUDGET_SECONDS = Integer(ENV.fetch("MASTER_FIX_RUN_BUDGET_S", 30 * 60))
      WORKFLOW_PATH = Master.limits_path.freeze

      def initialize(rules:, agent:, scanner:, root:, axioms: nil, bus: nil, git: nil, learnings: nil,
                     incremental: false, ground_truth: nil, preserve_user_intent: nil,
                     law_resolver: nil, homeostat: nil)
        @rules = rules
        @axioms = axioms
        @agent = agent
        path_root = File.expand_path(root)
        @root = path_root == Master::ROOT ? Master::REPO_ROOT : path_root
        @bus = bus
        @homeostat = homeostat
        @incremental = incremental
        @halted = false
        @halt_reason = nil
        @run_mutex = Mutex.new
        @git = git || Io::GitOperations.new(root)
        @run_journal = RunJournal.new(root:, bus:)
        @reachability = Reachability.new(root: @root, bus:)
        @transformation_plan = TransformationPlan.new(root: Master::ROOT)
        @wishlist = Wishlist.new(root: @root, agent: @agent, event_bus: @bus)
        @convergence_discipline = ConvergenceDiscipline.new(root: @root, bus: @bus)

        @file_collector = FileCollector.new(root:, bus:)
        @law_order = LawOrder.new(rules:, learnings:, bus:, root:)
        @pass_runner = build_pass_runner(rules:, agent:, scanner:, root:, bus:, learnings:,
          ground_truth:, preserve_user_intent:, law_resolver:, homeostat: @homeostat,
          discipline: @convergence_discipline, wishlist: @wishlist)
        @sweeps = build_sweeps(agent:, root:, bus:)
      end

      # A halt stops the runs nobody asked for, the background runner and the
      # watcher, when MASTER's own tree reads red. An operator's /fix is the
      # request to repair exactly that tree; halting it too refused every fix
      # while a single violation stood, so "fix and commit" scanned and stopped.
      def run(target = @root, max_passes: max_passes_default, budget_seconds: RUN_BUDGET_SECONDS,
              incremental: @incremental, requested: false)
        @run_mutex.synchronize do
          run_unlocked(target, max_passes:, budget_seconds:, incremental:, requested:)
        end
      end

      def run_unlocked(target, max_passes:, budget_seconds:, incremental:, requested:)
        mission = nil
        current_phase = :preflight
        return halted_result if halted? && !requested

        current_phase = :corpus
        files = incremental ? @file_collector.collect_changed(target) : @file_collector.collect(target)
        @pass_runner.full_semantic! if requested && @pass_runner.respond_to?(:full_semantic!)
        coverage = {
          candidates: @file_collector.candidate_count,
          collected: files.size,
          skipped: @file_collector.skipped,
        }
        @bus&.publish("fix_loop:corpus", target:, **coverage)
        Master::Trace::Dmesg.status(
          "fix0",
          "corpus candidates=#{coverage[:candidates]} collected=#{coverage[:collected]} skipped=#{coverage[:skipped]}",
        )
        if coverage[:candidates].positive? && files.empty?
          reasons = @file_collector.skip_reasons.sort_by { |reason, count| [-count, reason] }
          detail = reasons.first(4).map { |reason, count| "#{reason}=#{count}" }.join(", ")
          suffix = detail.empty? ? "" : " (#{detail})"
          return Result.err(
            "fix_loop: corpus collected zero files from #{coverage[:candidates]} candidates#{suffix}",
            category: :validation
          )
        end
        current_phase = :begin_run
        @convergence_discipline.begin_run(files)
        current_phase = :journal
        journal = @run_journal.start_or_resume(target:, files:, max_passes:, budget_seconds:)
        run_id = journal["id"]
        mission = mission_for(target:, requested:)
        budget_error = exhausted_budget(journal:, run_id:)
        if budget_error
          mission.defer!(reason: budget_error.message)
          return budget_error
        end

        current_phase = :pass
        run_journaled(journal, files:, target:, max_passes:, budget_seconds:, mission:, requested:)
      rescue StandardError => e
        payload = {
          error_class: e.class.name,
          error_message: e.message,
          phase: current_phase.to_s,
          run_id: (defined?(run_id) ? run_id : nil),
          backtrace: e.backtrace&.first(8),
        }
        @bus&.publish("fix_loop:crash", **payload)
        Master::Trace::Dmesg.status(
          "fix0",
          "crash #{e.class} @ #{current_phase}: #{e.message.to_s[0, 180]}",
        )
        result = Result.err(
          "fix_loop: crash #{e.class} @ #{current_phase}: #{e.message} @ #{e.backtrace&.first(3)&.join(" | ")}",
          category: :crash,
        )
        if defined?(run_id) && run_id
          begin
            return finish_run(result, target, run_id, mission:, requested:)
          rescue StandardError => finish_error
            Master::Ground::Swallow.log(
              finish_error,
              context: "fix_loop.crash_terminal",
              event_bus: @bus,
            )
            @run_journal&.crash(run_id, "#{e.class}: #{e.message}; terminalization failed: #{finish_error.class}: #{finish_error.message}")
          end
        end
        result
      end

      def finish_run(result, target, run_id, mission: nil, requested: false)
        state = terminal_state_for(result)
        @run_journal.terminal(run_id, state, message: result.to_s)

        if mission&.requeue_if_requested!
          @bus&.publish("fix_loop:mission_requeued", run_id:, state:, reason: "wake received during attempt")
        elsif state == :done
          mission&.finish!(state: "completed", summary: result.to_s)
        elsif %i[human_decision blocked].include?(state)
          mission&.block!(reason: result.to_s)
        else
          mission&.defer!(reason: "attempt #{state}: #{result.to_s}")
        end

        @bus&.publish("fix_loop:terminal", state:, message: result.to_s)

        result
      end

      # Structural sweeps run outside repair transactions: a rename or restructure
      # moves files the pass transaction tracks by path, so each kept change is
      # isolated and returns to fresh observation.
      def sweep_tree(target, run_id, phase: :normal)
        changes = []
        errors = []

        @sweeps.each do |sweep|
          changes.concat(Array(sweep.run(target:, run_id:, phase:)))
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.#{sweep.class.name.split("::").last}", event_bus: @bus)
          errors << e
        end

        return changes if errors.empty?

        details = errors.map { |error| "#{error.class}: #{error.message}" }.join(" | ")
        raise "structural sweep failed: #{details}"
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
        structure = @sweeps.filter_map do |sweep|
          sweep.preview(target:, run_id: "preview") if sweep.respond_to?(:preview)
        end.flatten
        Result.ok(
          total: violations.size,
          rules: by_rule.sort_by { |_, n| -n }.first(10).to_h,
          files: by_file.sort_by { |_, n| -n }.first(10).to_h,
          structure:,
          transformation_order: @transformation_plan.operations.map(&:name),
          coverage: {
            candidates: @file_collector.candidate_count,
            collected: files.size,
            skipped: @file_collector.skipped,
          },
        )
      end

      def collect_files(target) = @file_collector.collect(target)

      def ordered_laws(violation_counts: {})
        @law_order.ordered(violation_counts:)
      end

      def self.preamble_from_soul = [LawLoop.soul_preamble, Protocol.instruction].join("\n\n")

      private

      # The look back over the tree after the repair passes: structural consolidation,
      # then naming cleanup. Both work from the repository root.
      def build_sweeps(agent:, root:, bus:)
        repo_root = File.basename(root) == "MASTER" ? File.expand_path("..", root) : root
        restructure = RestructureSweep.new(agent:, repo_root:, bus:, transformation_plan: @transformation_plan)
        [restructure, RenameSweep.new(agent:, repo_root:, bus:)]
      end

      # The run once its journal is open and a mission records it: resume what
      # an earlier process left, then the passes, then the terminal state.
      def run_journaled(journal, files:, target:, max_passes:, budget_seconds:, mission:, requested:)
        run_id = journal["id"]
        files = StreamCursor.order(@root, target, files)
        deadline = Ground::Reliability::Deadline.new(journal["remaining_seconds"].to_f)
        start_pass = @run_journal.next_pass(journal)
        @bus&.publish("fix_loop:recovered", run_id:, start_pass:, target:) if journal["resumed"]

        @reachability.verify!(target, files:)

        resumed = resume_active_transaction(journal:, run_id:, start_pass:)
        return resumed.tap { mission.fail!(resumed.message) } if resumed.err?

        result = run_passes(
          files:, target:, max_passes:, deadline:, budget_seconds:,
          start_pass: resumed.value!, run_id:, wishlist_proposals: []
        )
        result = continue_with_wishlist(result, files:, target:, max_passes:, budget_seconds:, run_id:)
        finish_run(result, target, run_id, mission:, requested:)
      end

      def mission_for(target:, requested: false)
        checkpoint = lambda do |id:, root:, files:|
          Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints")).create(
            label: "mission-#{id}", files:,
          )
        end
        Master::Fix::Mission.new(root: @root, bus: @bus, checkpoint:).start_or_resume!(
          goal: "fix #{relative_target(target)}",
          scope: target,
          model: @agent.respond_to?(:model) ? @agent.model : ENV["MASTER_MODEL"],
          effort: ENV.fetch("MASTER_EFFORT", "high"),
          plan: mission_plan(target:),
          origin: requested ? "manual" : "supervisor",
        )
      rescue StandardError => e
        @bus&.publish("mission:error", error: e.message, phase: "start")
        raise
      end

      def mission_plan(target:)
        parts = [Ground::ActivePlan.read(@root), Wishlist.pending_context(@root, target:, limit: Wishlist::BATCH_SIZE)].compact
        parts << @transformation_plan.prompt
        parts.empty? ? "fix plan: observe, critique, repair, verify" : parts.join("\n\n")
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
        return :crash if result.err? && result.category == :crash
        return :skip if result.err? && result.category == :skip
        return result.value!.to_s[/\A[A-Z_]+/].to_s.downcase.to_sym if result.ok?

        :failed
      end

      # start_pass is the number of the first pass to run, 1-based like the
      # journal's next_pass; run_one_pass takes the 0-based index.
      def run_passes(files:, target:, max_passes:, deadline:, budget_seconds:, start_pass: 1, run_id:,
                     wishlist_proposals: [])
        state = { history: [], seen_snapshots: Set.new, recurring_violations: Hash.new(0), consecutive_clean: 0 }

        first_index = start_pass - 1
        pass_limit = [max_passes.to_i, ABSOLUTE_MAX_PASSES].min
        first_limit = pass_limit

        loop do
          remaining_passes = [pass_limit - first_index, 0].max

          remaining_passes.times do |offset|
            i = first_index + offset
            active_wishlist = i == first_index ? wishlist_proposals : []
            outcome = run_one_pass(
              i, files:, target:, deadline:, budget_seconds:, state:, run_id:,
              wishlist_proposals: active_wishlist
            )
            return terminal(:plateau, "no further improvement after #{i + 1} pass(es)") if outcome == :break
            return outcome if outcome

            if i == 0 && structural_target?(target)
              structure_checkpoint(target:, files:, run_id:)
            end
          end

          break unless @convergence_discipline.improving?
          break if pass_limit >= ABSOLUTE_MAX_PASSES
          break if deadline.expired?

          extension = [ADAPTIVE_PASS_CHUNK, ABSOLUTE_MAX_PASSES - pass_limit].min
          break if extension <= 0

          pass_limit += extension
          Master::Trace::Dmesg.status(
            "fix0",
            "extending convergence budget #{first_limit}->#{pass_limit}, measured improvement continues",
          )
          @bus&.publish(
            "fix_loop:adaptive_extension",
            run_id:, from_passes: first_limit, to_passes: pass_limit, chunk: extension,
          )
          first_limit = pass_limit
          # The next loop begins at the pass after the one just completed.
          first_index = pass_limit - extension
        end

        return terminal(:plateau, "adaptive pass budget exhausted at #{pass_limit}") if pass_limit >= ABSOLUTE_MAX_PASSES

        # The initial bound was reached without another measurable improvement.
        terminal(:plateau, "pass limit (#{pass_limit}) reached")
      end

      # Structural surgery is a post-delivery checkpoint, not the first thing
      # a full-tree run spends its budget on. The first ordinary pass gets to
      # deliver a verified repair; only then does the bounded structural sweep
      # run against freshly observed files.
      def continue_with_wishlist(result, files:, target:, max_passes:, budget_seconds:, run_id:)
        state = terminal_state_for(result)
        return result unless %i[done plateau].include?(state)

        wishlist_message = @wishlist.call(state: state.to_s, target:, run_id:)
        @bus&.publish("fix_loop:wishlist", state:, target:, message: wishlist_message)

        rounds = 0
        while rounds < WISHLIST_MAX_ROUNDS
          pending = @wishlist.claimable(target:, limit: Wishlist::BATCH_SIZE, run_id:)
          break if pending.empty?

          claimed = @wishlist.claim(pending, run_id:)
          break if claimed.empty?

          remaining = @run_journal.remaining_seconds(run_id)
          break if remaining < WISHLIST_MIN_REMAINING_SECONDS

          run_record = @run_journal.history(limit: RunJournal::MAX_RUNS).find { |row| row["id"] == run_id }
          start_pass = @run_journal.next_pass(run_record)
          refreshed = @file_collector.collect(target)
          round_passes = [WISHLIST_MAX_PASSES, max_passes].min
          round_max_pass = start_pass + round_passes - 1
          deadline = Ground::Reliability::Deadline.new(remaining)

          Master::Trace::Dmesg.status(
            "fix0",
            "wishlist round #{rounds + 1}: #{claimed.size} proposal(s), #{remaining.round}s remaining",
          )

          result = run_passes(
            files: refreshed,
            target:,
            max_passes: round_max_pass,
            deadline:,
            budget_seconds: remaining,
            start_pass:,
            run_id:,
            wishlist_proposals: claimed,
          )

          if terminal_state_for(result) == :done
            verification = @wishlist.mark_verified(
              proposal_ids: claimed.map { |proposal| proposal["uid"] },
              run_id:,
            )
            blocked = verification.count { |row| row["status"] == "blocked" }
            open = verification.count { |row| row["status"] == "applied" }
            if blocked.positive?
              result = terminal(:blocked, "wishlist proof failed for #{blocked} applied proposal(s)")
            elsif open.positive?
              result = terminal(:plateau, "wishlist proof inconclusive for #{open} applied proposal(s)")
            end
          end

          rounds += 1
          next if %i[done plateau].include?(terminal_state_for(result))

          break
        end

        remaining_pending = @wishlist.pending_count(target:)
        if remaining_pending.positive? && %i[done plateau].include?(terminal_state_for(result))
          result = terminal(
            :plateau,
            "wishlist queue retained #{remaining_pending} supported proposal(s) after #{rounds} bounded round(s)",
          )
        end
        result
      rescue StandardError => e
        @bus&.publish("fix_loop:wishlist_error", error: e.message, target:, run_id:)
        Result.err("wishlist convergence failed: #{e.class}: #{e.message}", category: :unknown)
      end

      def structure_checkpoint(target:, files:, run_id:)
        return if ENV["MASTER_FIX_STRUCTURE_FIRST"] == "0"

        changes = sweep_tree(target, "#{run_id}-structure-checkpoint", phase: :structure_first)
        return if changes.empty?

        files.replace(@file_collector.collect(target))
        Master::Trace::Dmesg.status("fix0", "structure checkpoint kept #{changes.size}; corpus refreshed")
        @bus&.publish("fix_loop:structure_checkpoint", target:, changes: changes.size)
      end

      def structural_target?(target)
        expanded = File.expand_path(target.to_s)
        repo_root = File.basename(@root) == "MASTER" ? File.expand_path("..", @root) : File.expand_path(@root)
        return true if expanded == repo_root
        return false unless %w[MASTER RAILS OPENBSD STUDIO].include?(File.basename(expanded))

        File.dirname(expanded) == repo_root
      end

      # Every ending carries its state, so a caller cannot read "clean after 2
      # passes" as "the tree is done" when the loop merely stopped.
      def terminal(state, message)
        raise ArgumentError, "unknown terminal state: #{state}" unless TERMINAL_STATES.include?(state)

        Result.ok("#{state.to_s.upcase}: #{message}")
      end

      def run_one_pass(i, files:, target:, deadline:, budget_seconds:, state:, run_id:, wishlist_proposals:)
        pass = i + 1
        transaction_id = "#{run_id}-pass-#{pass}"
        @run_journal.pass_start(run_id, pass, transaction_id:)

        @homeostat&.observe(:tool_call) # a pass is loop overhead distinct from the LLM call inside it
        return timed_out(i, pass, budget_seconds) if deadline.expired?

        result = @pass_runner.run_pass(
          files:, target:, pass:, deadline: deadline.at, transaction_id:,
          history: state[:history], seen_snapshots: state[:seen_snapshots],
          recurring_violations: state[:recurring_violations],
          consecutive_clean: state[:consecutive_clean],
          wishlist_proposals:, run_id:
        )
        @convergence_discipline.note_progress! if @pass_runner.respond_to?(:pass_progress?) && @pass_runner.pass_progress?
        if %i[continue reloading].include?(result.status) && wishlist_proposals.any?
          @wishlist.mark_delivered(
            proposal_ids: wishlist_proposals.map { |proposal| proposal["uid"] },
            run_id:,
          )
        end
        state[:consecutive_clean] = result.consecutive_clean
        return nil if structural_repair?(result, files:, target:, state:, run_id:, pass:)

        @run_journal.pass_finish(run_id, pass, status: result.status, message: result.message)
        ending = PASS_ENDINGS[result.status]
        return terminal(ending, result.message) if ending

        result.status == :plateau ? :break : nil
      end

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
      def timed_out(i, pass, budget_seconds)
        @bus&.publish("fix_loop:timeout", pass:, budget_seconds:)
        Result.err("wall-clock timeout (#{budget_seconds}s) after #{i} pass(es)", category: :timeout)
      end

      # A clean or plateaued pass gets structural surgery; anything it keeps
      # sends the loop back into repair with the new file list.
      def structural_repair?(result, files:, target:, state:, run_id:, pass:)
        return false unless %i[clean plateau].include?(result.status)

        structural = sweep_tree(target, run_id, phase: :normal)
        return false if structural.empty?

        state[:consecutive_clean] = 0
        files.replace(@file_collector.collect(target))
        message = "structural surgery kept #{structural.size}; re-entering repair"
        @run_journal.pass_finish(run_id, pass, status: :structural_repair, message:)
        @bus&.publish("fix_loop:structural_repair", pass:, changes: structural.size)
        Master::Trace::Dmesg.status("fix0", "pass #{pass}, #{message}")
        true
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