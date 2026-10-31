# frozen_string_literal: true

require_relative "../kernel"
require_relative "../final_cleanup"

# Install the historical constant before child files reopen FixLoop. Keeping
# both names on the same class object prevents parallel coordinator graphs.
module Master
  module Fix
    remove_const(:FixLoop) if autoload?(:FixLoop, false)
    const_set(:FixLoop, Kernel::ConvergenceAdapter) unless const_defined?(:FixLoop, false)
  end
end

require_relative "../run_journal"
require "set"
require "time"
require_relative "../scanner"
require_relative "../fix_plan"
require_relative "../reachability"
require_relative "../instrument_check"
require_relative "../fix_loop/committer"
require_relative "../fix_loop/council_round"
require_relative "../fix_loop/llm_router"
require_relative "../fix_loop/file_collector"
require_relative "../fix_loop/order"
require_relative "../fix_loop/pass_runner"
require_relative "../check_focus"
require_relative "../work_lane"
require_relative "../visual_lane_world"
require_relative "../fix_loop/convergence_config"
require_relative "../fix_loop/background_runner"
require_relative "../fix_loop/pass_runner_builder"
require_relative "../fix_loop/completion"
require_relative "../fix_loop/lifecycle"
require_relative "../fix_loop/pass_execution"
require_relative "../outcome_learning"
require_relative "../visual_pass"
require_relative "../opportunity_pass"
require_relative "../rename_sweep"
require_relative "../severity"
require_relative "../violation"
require_relative "../wishlist"
require_relative "../outcome_policy"
require_relative "../protocol"
require_relative "../architecture_exploration"
require_relative "../transformation_plan"
require_relative "../../review/reference_graph"
require_relative "../research_pass"
require_relative "../convergence_discipline"
require_relative "../reflection"
require_relative "../run_budget"
require_relative "../run_ledger"
require_relative "../../boot/paths"

module Master
  module Fix
    class Kernel
      # Observe, critique, repair and observe again until the tree converges, stops
      # improving, or reaches a state MASTER may not settle on its own. A run ends
      # in one of TERMINAL_STATES and says which: "complete" for a run that merely
      # ran out of passes is the false completion this loop exists to refuse.
      class ConvergenceAdapter
      attr_reader :homeostat, :kernel
      # How the last run ended, as a TERMINAL_STATES symbol, for the pass to read instead of its message.
      attr_reader :last_terminal_state

      # Where this loop keeps its mission: the repository root when it serves MASTER. The Fold's
      # mission stays under MASTER's root; the two are different work and both may be live.
      def mission_root = @root

      include ConvergenceConfig
      include BackgroundRunner
      include PassRunnerBuilder
      include Completion
      include Lifecycle
      include PassExecution
      include OutcomeLearning

      # How a run is allowed to end, and every ending says which it was. DONE is
      # the only one that claims the work is finished: the tree observed clean
      # the required number of times in a row, with the ground truth agreeing.
      # PLATEAU is convergence without that proof — the same findings keep
      # coming back, or the passes ran out. HUMAN_DECISION is a safe halt when a
      # proposed fix is irreversible or spans multiple files. BLOCKED is a halt
      # outside the loop's authority, and VALIDATION_FAILED is a repair the tree refused.
      # OutcomePolicy is canonical; Protocol derives its wire spelling from it.
      TERMINAL_STATES = OutcomePolicy::TERMINAL_STATES
      # A pass status that ends the run, and the state it ends in.
      PASS_ENDINGS = { clean: :done, blockers_cleared: :done, validation_failed: :validation_failed,
                       delivery_failed: :delivery_failed, human_decision: :human_decision,
                       reloading: :reloading, cancelled: :cancelled, unknown_outcome: :unknown_outcome,
                       recovery_failed: :recovery_failed }.freeze
      MEASURED_REPAIR_OUTCOMES = OutcomePolicy::MEASURED_REPAIR_OUTCOMES

      MAX_PASSES = 15
      ADAPTIVE_PASS_CHUNK = Integer(ENV.fetch("MASTER_FIX_ADAPTIVE_PASS_CHUNK", 3))
      ABSOLUTE_MAX_PASSES = Integer(ENV.fetch("MASTER_FIX_ABSOLUTE_MAX_PASSES", 60))
      # Two evidence-backed clean passes are the minimum; operators may raise,
      # but never lower, the completion bar.
      CLEAN_RUNS = [Integer(ENV.fetch("MASTER_FIX_CLEAN_RUNS", 2)), 2].max
      # Five passes without improvement before a plateau stops the run, as
      # laws.yml transformation_policy.exit.plateau says; three stopped work
      # that a slow pass was still about to land (operator, 2026-10-31).
      PLATEAU_WINDOW = 5
      # Rounds of improvement proposals after a run finishes: asked for, never by default, because
      # each round is up to three more passes once the work requested is done.
      WISHLIST_MAX_ROUNDS = Integer(ENV.fetch("MASTER_FIX_WISHLIST_ROUNDS", 0))
      WISHLIST_MAX_PASSES = 3
      WISHLIST_MIN_REMAINING_SECONDS = 60

      def initialize(laws:, agent:, scanner:, root:, axioms: nil, bus: nil, git: nil, learnings: nil,
                     incremental: false, ground_truth: nil, preserve_user_intent: nil,
                     law_resolver: nil, homeostat: nil, reference_graph: nil, kernel: nil)
        @laws = laws
        @axioms = axioms
        @agent = agent
        path_root = File.expand_path(root)
        @cognition_root = path_root
        @root = path_root == Master::ROOT ? Master::REPO_ROOT : path_root
        # Where the pass runner persists its transactions: the root given here, not the
        # repository root above. Recovery read the repository root, so a crashed pass's
        # transaction was never found and its half-applied tree was never restored.
        @transaction_root = path_root
        @bus = bus
        @reference_graph = reference_graph || Master::Review::ReferenceGraph.new(root: @root, event_bus: bus)
        @homeostat = homeostat
        @cognition = nil
        @outcome_prior = nil
        @incremental = incremental
        @halted = false
        @halt_reason = nil
        @git = git || Io::GitOperations.new(root)
        # Production boot injects the shared Kernel. Standalone callers keep
        # working by creating one owner for this loop, never one per stage.
        @kernel = kernel || Kernel.new(root: path_root, actor: "fix-loop", bus:)
        @run_mutex = @kernel.execution_mutex
        @run_journal = @kernel.lifecycle_journal
        @reachability = Reachability.new(root: @root, bus:)
        @transformation_plan = TransformationPlan.new(root: Master::ROOT)
        @wishlist = Wishlist.new(root: @root, agent: @agent, event_bus: @bus)
        @convergence_discipline = ConvergenceDiscipline.new(root: @root, bus: @bus, cognition_root: @cognition_root)
        @reflection = Reflection.new(agent: @agent, root: @root, bus: @bus)

        @file_collector = FileCollector.new(root:, bus:)
        @pass_runner = build_pass_runner(laws:, agent:, scanner:, root:, bus:, learnings:,
          ground_truth:, preserve_user_intent:, law_resolver:, homeostat: @homeostat,
          discipline: @convergence_discipline, wishlist: @wishlist, reference_graph: @reference_graph,
          kernel: @kernel)
        @sweeps = build_sweeps(agent:, root:, bus:, ground_truth:, preserve_user_intent:)
      end

      # --blockers: the corpus is the files a red check named before the repair, nothing else.
      def blocker_files(files)
        named = CheckFocus.only(files)
        Master::Trace::Dmesg.status("fix0", "blockers: #{named.size} of #{files.size} file(s) named by a red check")
        named
      end

      # Files the last run could not scan, read semantically, or finish a stage on, for its scorecard.
      def gap_count = Array(@pass_runner&.gaps&.values).sum(&:size)

      # What /fix measures with, tried before anything is read: the check run_journaled repeats on entry.
      def instrument_failures = InstrumentCheck.new(root: @root, bus: @bus).broken

      # A halt stops the runs nobody asked for, the background runner and the
      # watcher, when MASTER's own tree reads red. An operator's /fix is the
      # request to repair exactly that tree; halting it too refused every fix
      # while a single violation stood, so "fix and commit" scanned and stopped.
      def run(target = @root, max_passes: max_passes_default, budget_seconds: FixTime.run_s,
              incremental: @incremental, requested: false, cancellation: nil)
        @kernel.run_fix_loop(
          self, target:, max_passes:, budget_seconds:, incremental:, requested:, cancellation:
        )
      end

      def cancellation_requested? = @cancellation&.cancelled? == true

      def cancellation_terminal
        reason = @cancellation.respond_to?(:reason) ? @cancellation.reason : nil
        detail = reason.to_s.strip
        message = detail.empty? ? "/fix cancelled at a safe stage boundary" :
          "/fix cancelled at a safe stage boundary (#{detail})"
        Result.err("CANCELLED: #{message}", category: :cancelled)
      end

      def run_unlocked(target, max_passes:, budget_seconds:, incremental:, requested:)
        mission = nil
        @last_terminal_state = nil
        current_phase = :preflight
        return cancellation_terminal if cancellation_requested?
        return halted_result if halted? && !requested

        recover_stranded_transactions!
        @pass_runner&.reset_gaps!
        @pass_runner.research_brief = nil if @pass_runner&.respond_to?(:research_brief=)
        # A requested /fix owes a semantic read to every file with a cheap finding and to a rotating
        # slice of the clean ones (Ground::ModePosture.semantic_sample); a file read before and
        # unchanged is not read again (Scan::FindingCache). A pass makes only a budget's worth of
        # those reads, after its mechanical repairs are queued (PassRunner::StreamStage), and the
        # next pass resumes where it stopped, so every file is read across runs. Reading them inline
        # held the first repair for hours. MASTER_SCAN_SEMANTIC_SAMPLE=1 owes a read to every file.
        @pass_runner.full_semantic! if requested && @pass_runner&.respond_to?(:full_semantic!)
        guidance = outcome_guidance(target:, incremental:)
        # A requested /fix lints every line of every eligible file; only an unattended run may sample.
        incremental = requested ? false : guidance.fetch(:incremental)
        @fix_plan_incremental = incremental
        @outcome_prior = guidance[:prediction]
        Master::Io::LaneSelection.announce
        current_phase = :corpus
        files = incremental ? @file_collector.collect_changed(target) : @file_collector.collect(target)
        files = blocker_files(files) if CheckFocus.blockers?
        coverage = {
          candidates: @file_collector.candidate_count,
          collected: files.size,
          skipped: @file_collector.skipped,
          blocking_skips: @file_collector.respond_to?(:blocking_skips) ? @file_collector.blocking_skips : {},
        }
        @bus&.publish("fix_loop:corpus", target:, **coverage)
        Master::Trace::Dmesg.status(
          "fix0",
          "corpus candidates=#{coverage[:candidates]} collected=#{coverage[:collected]} skipped=#{coverage[:skipped]}",
        )
        note_uninspectable(coverage[:blocking_skips])
        if coverage[:candidates].positive? && files.empty?
          reasons = @file_collector.skip_reasons.sort_by { |reason, count| [-count, reason] }
          detail = reasons.first(4).map { |reason, count| "#{reason}=#{count}" }.join(", ")
          suffix = detail.empty? ? "" : " (#{detail})"
          return Result.err(
            "fix_loop: corpus collected zero files from #{coverage[:candidates]} candidates#{suffix}",
            category: :validation,
          )
        end
        # Open the durable run and start its single budget before graph building
        # or research. Previously both expensive stages ran before the journal and
        # watchdog existed, so they could consume the whole allowance invisibly.
        current_phase = :journal
        journal = @run_journal.start_or_resume(target:, files:, max_passes:, budget_seconds:)
        run_id = journal["id"]
        @kernel.bind_fix_run(
          adapter: self, run_id:, target:, max_passes:, budget_seconds:, requested:,
        )
        mission = mission_for(target:, requested:)
        @kernel.link_fix_mission(mission_id: mission.id, run_id:)
        budget_error = exhausted_budget(journal:)
        if budget_error
          # A prior process can die mid-pass after spending the budget. Recover
          # its persisted transaction before returning the timeout, otherwise
          # each later /fix strands the same half-applied tree forever.
          stranded = @run_journal.active_pass(journal)
          transaction_id = stranded.is_a?(Hash) ? stranded["transaction_id"] : nil
          if transaction_id && Transaction::Recovery.persisted?(root: @transaction_root, id: transaction_id)
            recovered = resume_active_transaction(
              journal:, run_id:, start_pass: @run_journal.next_pass(journal),
            )
            return finish_run(recovered, target, run_id, mission:, requested:) if recovered.err?
          end

          # The expired run ends with its canonical terminal event, and this
          # invocation's own budget opens a fresh run. Ending here instead cost
          # the whole MASTER target of a four-tree /fix on 2026-10-26.
          finish_run(budget_error, target, run_id, mission:, requested:)

          journal = @run_journal.start_or_resume(target:, files:, max_passes:, budget_seconds:)
          run_id = journal["id"]
          @kernel.bind_fix_run(
            adapter: self, run_id:, target:, max_passes:, budget_seconds:, requested:,
          )
          mission = mission_for(target:, requested:)
          @kernel.link_fix_mission(mission_id: mission.id, run_id:)
          budget_error = exhausted_budget(journal:)
          return finish_run(budget_error, target, run_id, mission:, requested:) if budget_error
        end

        RunBudget.begin_run(root: Master::ROOT, max_passes:, bus: @bus, target:)
        journal["budget_clock_at"] = RunBudget.elapsed_seconds
        # Capture the immutable plan inside the run's measured budget, but before
        # any structure/repair mutation. Hashing a large corpus is real work and
        # must not happen invisibly ahead of the run journal or watchdog.
        current_phase = :plan
        canonical_root = File.expand_path(defined?(Master::REPO_ROOT) ? Master::REPO_ROOT : @root)
        expanded_target = File.expand_path(target.to_s, @root)
        managed_target = expanded_target == canonical_root ||
          expanded_target.start_with?(canonical_root + File::SEPARATOR)
        repository_root = managed_target ? canonical_root : File.expand_path(@root)
        exclusions = {
          counts: @file_collector.skip_reasons,
          paths: @file_collector.excluded_path_reasons,
          sample: @file_collector.excluded_path_reasons.keys.sort.first(FixPlan::MAX_EXCLUSION_SAMPLE),
        }
        @fix_plan = FixPlan.capture(
          root: repository_root, target:, files:, laws: @laws, excluded: exclusions,
          adapters: @pass_runner.assessment_adapters(target:),
          max_passes:, budget_seconds:
        )
        @bus&.publish("fix_loop:plan", **@fix_plan.to_h.slice(
          "digest", "identity_digest", "source_digest", "scope_digest", "law_digest",
          "law_source_digest", "authority_digest", "toolchain_digest", "exclusion_digest",
          "adapter_digest", "eligible_files", "excluded", "adapters", "max_passes",
          "budget_seconds", "deadline_at"
        ).transform_keys(&:to_sym))
        bind_fix_plan!(journal, run_id)
        @pass_runner.begin_assessment_run(files:, plan: @fix_plan) if
          @pass_runner.respond_to?(:begin_assessment_run)
        if RunBudget.stopping || repair_seconds_left(journal) <= 0
          exhausted = RunBudget.pass_boundary(0) ||
            Result.err("wall-clock timeout during fix-plan capture; no repair pass ran", category: :timeout)
          return finish_run(exhausted, target, run_id, mission:, requested:)
        end
        return finish_run(cancellation_terminal, target, run_id, mission:, requested:) if cancellation_requested?

        current_phase = :begin_run
        @convergence_discipline.begin_run(files)
        return finish_run(cancellation_terminal, target, run_id, mission:, requested:) if cancellation_requested?

        if requested
          current_phase = :structure
          dependency_result = prepare_dependency_map!(files)
          return finish_run(cancellation_terminal, target, run_id, mission:, requested:) if cancellation_requested?
          return finish_run(dependency_result, target, run_id, mission:, requested:) if dependency_result.is_a?(Master::Result)
          current_phase = :architecture_exploration
          architecture = explore_architecture(target:, files:, run_id:)
          return finish_run(cancellation_terminal, target, run_id, mission:, requested:) if cancellation_requested?
          ux_context = UXRefinementCatalog.prompt_context(target:, root: @root)
          current_phase = :research
          research = run_research(target:, files:)
          return finish_run(cancellation_terminal, target, run_id, mission:, requested:) if cancellation_requested?
          @pass_runner.research_brief = [
            architecture.fetch("brief"),
            ux_context,
            research.fetch(:brief),
          ].reject { |part| part.to_s.strip.empty? }.join("\n\n")
        end
        current_phase = :pass
        run_journaled(journal, files:, target:, max_passes:, budget_seconds:, mission:, requested:, incremental:)
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
      ensure
        cleanup_run_resources(target:, run_id: (defined?(run_id) ? run_id : nil))
      end

      # Final cleanup is separate from repair decisions: it releases only resources
      # owned by this invocation, prunes journal-indexed artifacts, and reports
      # any failure without masking the actual repair result or crash.
      def cleanup_run_resources(target:, run_id:)
        FinalCleanup.new(
          root: @root, bus: @bus, kernel: @kernel, committer: @committer,
          pass_runner: @pass_runner, run_journal: @run_journal
        ).run(target:, run_id:, terminal_state: @last_terminal_state)
      rescue StandardError => error
        @bus&.publish(
          "fix_loop:cleanup",
          run_id:, target: "(cleanup stage error)", terminal_state: @last_terminal_state.to_s,
          status: "warning", warnings: [{ step: "cleanup_stage", error_class: error.class.name }]
        )
        Master::Trace::Dmesg.status("cleanup0", "warning, #{error.class}: #{error.message.to_s[0, 160]}") rescue nil
        nil
      end

      # Before a requested /fix can write, read every eligible text source
      # into the repository reference graph and refuse partial dependency maps.
      # The graph is refreshed per run; failed reads and corpus files with no
      # graph node are explicit gaps, not permission to guess.
      def prepare_dependency_map!(files)
        graph = @reference_graph
        snapshot = graph.build(refresh: true)
        failures = Array(snapshot[:analysis_failures])
        missing = Array(files).reject { |path| graph.includes_path?(path) }
        unless failures.empty? && missing.empty?
          detail = []
          detail << "#{failures.size} graph analysis failure(s): #{failures.first(3).map { |row| row[:path] }.join(", ")}" if failures.any?
          detail << "#{missing.size} eligible file(s) absent from dependency graph: #{missing.first(3).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}" if missing.any?
          message = "fix_loop: dependency understanding incomplete; no repair started (#{detail.join("; ")})"
          Master::Trace::Dmesg.status("understand0", "BLOCKED, #{message[0, 180]}")
          @bus&.publish("fix_loop:dependency_map_incomplete", failures: failures.size, missing: missing.size, detail:)
          return Result.err(message, category: :policy)
        end

        graph_metrics = snapshot.fetch(:metrics)
        Master::Trace::Dmesg.status(
          "understand0",
          "text-source graph indexed, nodes=#{snapshot[:nodes].size}, edges=#{snapshot[:edges].size}, " \
          "unresolved-ruby=#{graph_metrics[:unresolved_ruby_references]}, " \
          "unresolved-imports=#{graph_metrics[:unresolved_local_imports]}, " \
          "local-import-edges=#{graph_metrics[:resolved_local_import_edges]}, " \
          "dynamic-sites=#{graph_metrics[:dynamic_sites]}, analysis-failures=0",
        )
        @bus&.publish(
          "fix_loop:dependency_map_ready",
          nodes: snapshot[:nodes].size,
          edges: snapshot[:edges].size,
          unresolved_ruby_references: graph_metrics[:unresolved_ruby_references],
          unresolved_local_imports: graph_metrics[:unresolved_local_imports],
          resolved_local_import_edges: graph_metrics[:resolved_local_import_edges],
          dynamic_sites: graph_metrics[:dynamic_sites],
          analysis_failures: 0,
        )
        snapshot
      end

      # A file over the corpus limits (STUDIO/dilla/dilla.rb past the line limit) cannot be read, so
      # the run can never say DONE; it is a gap like an unread file, and the rest of the tree is
      # still repaired. Refusing the run for it left 133 STUDIO files unrepaired.
      def note_uninspectable(skips)
        @uninspectable = skips.to_h
        return if @uninspectable.empty?

        Master::Trace::Dmesg.status("fix0", "uninspectable inputs remain: #{uninspectable_detail}; repairing the rest")
      end

      def uninspectable = (@uninspectable ||= {})

      def uninspectable_detail = uninspectable.map { |reason, count| "#{reason}=#{count}" }.join(", ")

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

      # The one push of a run: called after final verification, and a no-op when
      # MASTER_FIX_PUSH=each already published every commit.
      def publish_pending!
        @pass_runner.publish_pending!
      end

      def retry_delivery(transaction_id:, expected_head:)
        transaction = Transaction::Recovery.load_persisted(root: @transaction_root, id: transaction_id, bus: @bus)
        return Result.err("delivery recovery transaction has no recorded commit", category: :policy) unless transaction.delivery.pending?
        return Result.err("delivery recovery commit identity mismatch", category: :policy) unless transaction.delivery.head_after.to_s == expected_head.to_s
        return Result.err("delivery recovery HEAD mismatch", category: :policy) unless @git.head == expected_head

        @git.push
        return Result.err("delivery recovery HEAD changed during push", category: :policy) unless @git.head == expected_head
        ahead, behind = @git.ahead_behind
        return Result.err("delivery recovery left ahead=#{ahead} behind=#{behind} commit(s) after push", category: :infrastructure) unless ahead.zero? && behind.zero?

        result = transaction.delivery.finalize!(head: expected_head)
        result.err? ? result : Result.ok(:delivery_recovered)
      rescue StandardError => e
        Result.err("delivery recovery: #{e.message}", category: :infrastructure)
      ensure
        transaction&.send(:release_lock)
      end

      def preview(target = @root)
        @pass_runner.reset_gaps!
        files = @file_collector.collect(target)
        violations = @pass_runner.preview_violations(files)
        by_law = violations.group_by { |v| v[:law].to_s }.transform_values(&:size)
        by_file = violations.group_by { |v| v[:file].to_s }.transform_values(&:size)
        structure = @sweeps.filter_map do |sweep|
          sweep.preview(target:, run_id: "preview") if sweep.respond_to?(:preview)
        end.flatten
        Result.ok(
          total: violations.size,
          laws: by_law.sort_by { |_, n| -n }.first(10).to_h,
          files: by_file.sort_by { |_, n| -n }.first(10).to_h,
          structure:,
          transformation_order: @transformation_plan.operations.map(&:name),
          blockers: CheckFocus.only(files).map { |path| path.delete_prefix("#{@root}/") },
          gaps: @pass_runner.gaps,
          coverage: {
            candidates: @file_collector.candidate_count,
            collected: files.size,
            skipped: @file_collector.skipped,
            semantic_inconclusive: @pass_runner.semantic_inconclusive.size,
          },
        )
      end

      def collect_files(target) = @file_collector.collect(target)

      def self.preamble_from_soul
        plan = TransformationPlan.new(root: Master::ROOT)
        [RepairLoop.soul_preamble, Protocol.instruction, plan.research_instructions].join("\n\n")
      end

      private

      # --lane visual: one sweep, grouped, mechanical fixers first, the model once per group left.
      def run_visual_lane(target)
        outcome = VisualLane.new(
          world: visual_world, repo_root: Master::REPO_ROOT,
          say: ->(line) { Master::Trace::Dmesg.status("visual0", line) },
          stop: -> { cancellation_requested? || RunBudget.stopping }
        ).run
        @bus&.publish("fix_loop:visual_lane", target:, **outcome.to_h)
        return cancellation_terminal if cancellation_requested?

        visual_terminal(outcome)
      end

      def visual_world
        tools = { reachability: @reachability, committer: @committer,
                  repair_loop: ->(brief) { visual_repair_loop(brief) } }
        VisualLaneWorld.new(repo_root: Master::REPO_ROOT, tools:, bus: @bus).world
      end

      # The lane proves only what its resweep shows, so a repaired but unmeasured group never
      # reads as DONE, and the ending says which lane ran and what it left.
      def visual_terminal(outcome)
        resweep = outcome.resweep ? "" : " (no repair, no resweep)"
        detail = "#{outcome.findings} rendered finding(s) in #{outcome.groups} group(s), " \
                 "#{outcome.cleared} cleared, #{outcome.remaining} group(s) remain#{resweep}; report #{outcome.report}"
        Master::Trace::Dmesg.status("visual0", "#{WorkLane.summary}; #{detail}")
        return terminal(:done, "visual lane: the sweep reported no rendered finding") if outcome.findings.zero?

        terminal(:plateau, "visual lane: #{detail}")
      end

      def visual_repair_loop(brief)
        @kernel.build_repair_loop(
          law: VisualPass::Law.new(VisualPass::LAW_ID), agent: @agent, scanner: @repair_kit.fetch(:scanner),
          root: @root, bus: @bus, learnings: @repair_kit.fetch(:learnings), committer: @committer, stage_commit: true
        ).tap { |loop| loop.injected_preamble = [@repair_kit.fetch(:preamble), brief].join("\n\n") }
      end

      # Both cost minutes of model and web time before the first repair; only --lane all asks for them.
      def explore_architecture(target:, files:, run_id:)
        unless WorkLane.runs?(:architecture)
          Master::Trace::Dmesg.status("fix0", "architecture exploration skipped, lane=#{WorkLane.current}")
          return { "status" => "SKIPPED", "targets" => [], "brief" => "" }
        end

        ArchitectureExploration.new(root: @root, agent: @agent, bus: @bus,
          run_journal: @run_journal, run_id:, provenance: @fix_plan&.to_h).run(target:, files:)
      end

      def run_research(target:, files:)
        unless WorkLane.runs?(:research)
          Master::Trace::Dmesg.status("research0", "skipped, lane=#{WorkLane.current}")
          return { status: "SKIPPED", brief: "" }
        end

        pass = ResearchPass.new(agent: @agent, bus: @bus, plan: @transformation_plan, root: @root)
        research = pass.run(target:, files:)

        Master::Trace::Dmesg.status(
          "research0",
          "#{research.fetch(:status)} domain=#{research.fetch(:domain)} " \
          "fetched=#{research.fetch(:fetched_count)} queries=#{research.fetch(:query_count)} " \
          "hosts=#{research.fetch(:independent_hosts, 0)} target=#{target}",
        )
        research
      end

      # The look back over the tree after the repair passes: structural consolidation,
      # then naming cleanup. Both work from the repository root.
      def build_sweeps(agent:, root:, bus:, ground_truth: nil, preserve_user_intent: nil)
        expanded_root = File.expand_path(root)
        repo_root = if MasterPaths::TREES.include?(File.basename(expanded_root))
                      File.expand_path("..", expanded_root)
                    else
                      expanded_root
                    end
        restructure = RestructureSweep.new(
          agent:, repo_root:, bus:, transformation_plan: @transformation_plan, ground_truth:, preserve_user_intent:,
        )
        [restructure, RenameSweep.new(agent:, repo_root:, bus:, ground_truth:, preserve_user_intent:)]
      end

      end
    end
  end
end
