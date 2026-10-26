# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      # Run-journal recovery, incremental scope verification and checkpoint
      # restoration. Effects use the shared Completion and OutcomePolicy
      # contracts; this module owns no second run ledger.
      module Lifecycle
        private

        def bind_fix_plan!(journal, run_id, plan = @fix_plan)
          binding = @run_journal.bind_plan(run_id, plan)
          return unless binding

          journal["plan"] = binding[:plan] if journal.is_a?(Hash)
          return binding unless binding[:invalidated]

          journal.delete("convergence_state") if journal.is_a?(Hash)
          journal.delete("pass_state") if journal.is_a?(Hash)
          @bus&.publish(
            "fix_loop:convergence_evidence_invalidated",
            run_id:, generation: binding[:generation], dimensions: binding[:dimensions]
          )
          Master::Trace::Dmesg.status(
            "fix0", "prior convergence evidence invalidated by #{binding[:dimensions].join(", ")}"
          )
          binding
        end

        # Re-observe the current eligible scope after each pass. A source, scope,
        # Law, authority, toolchain, exclusion or adapter change creates a new
        # evidence generation and resets convergence; inability to recapture is a gap.
        def refresh_fix_plan!(target:, files:, max_passes:, budget_seconds:, run_id:)
          collected = if @fix_plan_incremental && !structural_target?(target)
                        @file_collector.collect_changed(target)
                      else
                        @file_collector.collect(target)
                      end
          fresh_files = StreamCursor.order(@root, target, collected)
          fresh_files = blocker_files(fresh_files) if CheckFocus.blockers?
          files.replace(fresh_files) if Array(files).map { |path| File.expand_path(path) } !=
                                       fresh_files.map { |path| File.expand_path(path) }

          exclusions = {
            counts: @file_collector.skip_reasons,
            paths: @file_collector.excluded_path_reasons,
            sample: @file_collector.excluded_path_reasons.keys.sort.first(FixPlan::MAX_EXCLUSION_SAMPLE),
          }
          replacement = FixPlan.capture(
            root: @fix_plan.root,
            target:, files:, laws: @laws, excluded: exclusions,
            adapters: @pass_runner.assessment_adapters(target:),
            max_passes:, budget_seconds:
          )
          @pass_runner.plan_refresh_succeeded! if @pass_runner.respond_to?(:plan_refresh_succeeded!)
          current = @fix_plan
          dimensions = %i[
            scope_digest source_digest law_digest law_source_digest authority_digest
            toolchain_digest exclusion_digest adapter_digest
          ]
          changed = dimensions.select { |field| current.public_send(field) != replacement.public_send(field) }
          if changed.empty?
            # Refresh the filesystem signatures even when bytes and scope are
            # identical. A harmless touch must not leave the next pass comparing
            # against stale stat metadata or force a false source generation.
            @fix_plan = replacement
            return false
          end

          @fix_plan = replacement
          binding = bind_fix_plan!({}, run_id, replacement)
          @pass_runner.assessment_plan_changed!(replacement) if
            @pass_runner.respond_to?(:assessment_plan_changed!)
          @convergence_discipline.begin_run(files, preserve_run_baseline: true)
          @bus&.publish(
            "fix_loop:plan_generation",
            run_id:, generation: binding[:generation], changed_dimensions: changed,
            source_digest: replacement.source_digest, scope_digest: replacement.scope_digest,
            plan_digest: replacement.digest,
          )
          Master::Trace::Dmesg.status(
            "fix0",
            "new plan generation #{binding[:generation]}, changed=#{changed.join(", ")}; clean streak reset"
          )
          true
        rescue StandardError => e
          @pass_runner.plan_refresh_failed!(e) if @pass_runner.respond_to?(:plan_refresh_failed!)
          @bus&.publish(
            "fix_loop:plan_refresh_failed",
            run_id:, error_class: e.class.name, message: e.message
          )
          Master::Trace::Dmesg.status("fix0", "plan refresh INCONCLUSIVE: #{e.class}: #{e.message.to_s[0, 150]}")
          false
        end

        # The run once its journal is open and a mission records it: resume what
        # an earlier process left, then the passes, then the terminal state.
        def run_journaled(journal, files:, target:, max_passes:, budget_seconds:, mission:, requested:, incremental:)
          run_id = journal["id"]
          files = StreamCursor.order(@root, target, files)
          start_pass = @run_journal.next_pass(journal)
          @bus&.publish("fix_loop:recovered", run_id:, start_pass:, target:) if journal["resumed"]

          InstrumentCheck.new(root: @root, bus: @bus).verify!
          @reachability.verify!(target, files:, subset: CheckFocus.blockers?)

          resumed = resume_active_transaction(journal:, run_id:, start_pass:)
          return finish_run(resumed, target, run_id, mission:, requested:) if resumed.err?
          return finish_run(cancellation_terminal, target, run_id, mission:, requested:) if cancellation_requested?

          remaining = repair_seconds_left(journal)
          spent = budget_spent_before_pass(journal, resumed.value!) unless remaining.positive?
          return finish_run(spent, target, run_id, mission:, requested:) if spent

          deadline = Ground::Reliability::Deadline.new(remaining)

          if journal["resumed"] && journal["convergence_state"].is_a?(Hash) &&
             @convergence_discipline.respond_to?(:restore_checkpoint)
            restored = @convergence_discipline.restore_checkpoint(journal["convergence_state"])
            Master::Trace::Dmesg.status("fix0", "convergence history #{restored ? "restored" : "rejected"}")
          end

          result = run_passes(
            files:, target:, max_passes:, deadline:, budget_seconds:,
            start_pass: resumed.value!, run_id:, wishlist_proposals: [],
            resume_state: journal["resumed"] ? journal["pass_state"] : nil
          )
          return finish_run(cancellation_terminal, target, run_id, mission:, requested:) if cancellation_requested? ||
                                                                                         terminal_state_for(result) == :cancelled
          result = verify_incremental_scope(
            result, incremental:, journal:, target:, files:, max_passes:, deadline:, budget_seconds:, run_id:
          )
          return finish_run(cancellation_terminal, target, run_id, mission:, requested:) if cancellation_requested?
          result = reflect_then_continue(result, files:, target:, max_passes:, budget_seconds:, run_id:)
          result = cancellation_terminal if cancellation_requested? && terminal_state_for(result) == :done
          finish_run(result, target, run_id, mission:, requested:)
        end

        # The journal's budget runs from the moment the journal opened, so only what this process
        # spent since then (graph, research, recovery) comes off it. The command's baseline checks and
        # first observation ran before the journal and are bounded by MASTER_FIX_MAX_MINUTES instead:
        # charged here as well, a fifteen-minute RAILS baseline left the passes nothing.
        def repair_seconds_left(journal)
          now = RunBudget.elapsed_seconds
          spent = now - journal.fetch("budget_clock_at", now).to_f
          [journal["remaining_seconds"].to_f - [spent, 0.0].max, 0.0].max
        end

        # Nothing left for the passes is a timeout the run reports, never a Deadline it cannot build.
        def budget_spent_before_pass(journal, pass)
          budget = journal["remaining_seconds"].to_f.round
          Master::Trace::Dmesg.status("fix0", "repair budget #{budget}s spent before pass #{pass}; no pass ran")
          Result.err("fix budget (#{budget}s) spent before pass #{pass} began; no pass ran", category: :timeout)
        end

        # Incremental mode narrows repair work, never completion proof.
        # A clean changed-file run must recollect and verify the complete target
        # before its DONE verdict can reach reflection or mission completion.
        def verify_incremental_scope(result, incremental:, journal:, target:, files:, max_passes:, deadline:,
                                     budget_seconds:, run_id:)
          return result unless incremental && terminal_state_for(result) == :done

          full_files = StreamCursor.order(@root, target, @file_collector.collect(target))
          files.replace(full_files)
          blocking = @file_collector.respond_to?(:blocking_skips) ? @file_collector.blocking_skips : {}
          unless blocking.empty?
            detail = blocking.map { |reason, count| "#{reason}=#{count}" }.join(", ")
            return terminal(:blocked, "full-scope proof could not inspect target: #{detail}")
          end
          if @file_collector.candidate_count.positive? && full_files.empty?
            return terminal(:blocked, "full-scope proof collected no files from #{@file_collector.candidate_count} candidates")
          end
          return Result.err("full-scope proof exceeded the run deadline", category: :timeout) if deadline.expired?

          @reachability.verify!(target, files: full_files)
          run_record = @run_journal.history(limit: RunJournal::MAX_RUNS).find { |row| row["id"] == run_id }
          start_pass = @run_journal.next_pass(run_record || journal)
          if start_pass > ABSOLUTE_MAX_PASSES
            return terminal(:blocked, "full-scope proof could not start within the absolute pass limit")
          end

          @convergence_discipline.begin_run(full_files, preserve_run_baseline: true)
          proof_limit = [[max_passes.to_i, start_pass + CLEAN_RUNS - 1].max, ABSOLUTE_MAX_PASSES].min
          @bus&.publish(
            "fix_loop:full_scope_proof",
            run_id:, target:, files: full_files.size, start_pass:, pass_limit: proof_limit
          )
          Master::Trace::Dmesg.status("fix0", "incremental repair clean; verifying full target files=#{full_files.size}")
          run_passes(
            files: full_files, target:, max_passes: proof_limit, deadline:, budget_seconds:,
            start_pass:, run_id:, wishlist_proposals: []
          )
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

        # Route an expired resumed mission through finish_run just like an
        # in-flight timeout. Writing only the journal row here skipped the
        # canonical terminal event and outcome receipt, leaving observers with no
        # terminal state for a run that had already been started.
        def exhausted_budget(journal:)
          return if journal["remaining_seconds"].to_f.positive?

          Result.err("fix budget exhausted before resume", category: :timeout)
        end

        def resume_active_transaction(journal:, run_id:, start_pass:)
          active_pass = @run_journal.active_pass(journal)
          unless active_pass && Transaction::Recovery.persisted?(root: @root, id: active_pass.fetch("transaction_id"))
            return Result.ok(start_pass)
          end

          recovery = Transaction::Recovery.recover!(root: @root, id: active_pass.fetch("transaction_id"), bus: @bus)
          return recovery if recovery.err?
          return Result.ok(start_pass) unless recovery.value!.is_a?(Hash) && recovery.value![:state] == :delivery_pending

          recover_pending_delivery(active_pass:, run_id:, commit: recovery.value!.fetch(:commit))
        end

        def recover_pending_delivery(active_pass:, run_id:, commit:)
          recovery_result = retry_delivery(transaction_id: active_pass.fetch("transaction_id"), expected_head: commit)
          if recovery_result.err?
            return recovery_result unless recovery_result.category == :infrastructure

            return Result.err("delivery recovery failed: #{recovery_result.message}", category: :delivery_failed)
          end

          @run_journal.pass_finish(run_id, active_pass.fetch("pass"), status: :committed,
                                   message: "recovered Git delivery")
          Result.ok(active_pass.fetch("pass").to_i + 1)
        end

        def terminal_state_for(result)
          OutcomePolicy.terminal_state(result)
        end

        # start_pass is the number of the first pass to run, 1-based like the
        # journal's next_pass; run_one_pass takes the 0-based index.

        def durable_pass_state(state)
          {
            "version" => 1,
            "history" => Array(state[:history]).last(PLATEAU_WINDOW),
            "seen_snapshots" => Array(state[:seen_snapshots].to_a).last(ABSOLUTE_MAX_PASSES),
            "recurring_violations" => state[:recurring_violations].to_h,
            "consecutive_clean" => state[:consecutive_clean].to_i,
          }
        end

        def restore_pass_state(checkpoint)
          fresh = {
            history: [],
            seen_snapshots: Set.new,
            recurring_violations: Hash.new(0),
            consecutive_clean: 0,
          }
          return fresh if checkpoint.nil?
          unless checkpoint.is_a?(Hash) && checkpoint["version"] == 1
            Master::Trace::Dmesg.status("fix0", "invalid pass history checkpoint; starting a fresh cycle window")
            return fresh
          end

          history = checkpoint["history"]
          snapshots = checkpoint["seen_snapshots"]
          recurring = checkpoint["recurring_violations"]
          clean = checkpoint["consecutive_clean"]
          valid = history.is_a?(Array) && history.size <= PLATEAU_WINDOW &&
                  history.all? { |count| count.is_a?(Integer) && count >= 0 } &&
                  snapshots.is_a?(Array) && snapshots.size <= ABSOLUTE_MAX_PASSES &&
                  snapshots.all? { |digest| digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/) } &&
                  recurring.is_a?(Hash) &&
                  recurring.all? { |key, count| key.is_a?(String) && count.is_a?(Integer) && count >= 0 } &&
                  clean.is_a?(Integer) && clean >= 0
          unless valid
            Master::Trace::Dmesg.status("fix0", "malformed pass history checkpoint; starting a fresh cycle window")
            return fresh
          end

          {
            history: history.dup,
            seen_snapshots: Set.new(snapshots),
            recurring_violations: Hash.new(0).merge(recurring),
            consecutive_clean: clean,
          }
        end
      end
    end
  end
end
