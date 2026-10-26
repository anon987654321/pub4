# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      # The iterative repair cycle: passes, convergence, structural sweeps,
      # bounded follow-up rounds and terminal stop conditions. The top-level
      # FixLoop remains the public coordinator and preserves its instance API.
      module PassExecution
        private

        def run_passes(files:, target:, max_passes:, deadline:, budget_seconds:, start_pass: 1, run_id:,
                       wishlist_proposals: [], resume_state: nil)
          state = restore_pass_state(resume_state)

          first_index = start_pass - 1
          pass_limit = [max_passes.to_i, ABSOLUTE_MAX_PASSES].min
          first_limit = pass_limit
          stop_reason = nil

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
                if structure_checkpoint(target:, files:, run_id:)
                  state[:consecutive_clean] = 0
                  state[:history].clear
                  state[:seen_snapshots].clear
                  state[:recurring_violations].clear
                end
              end
            end

            decision = if @convergence_discipline.respond_to?(:adaptive_decision)
              @convergence_discipline.adaptive_decision(
                deadline_expired: deadline.expired?, pass_limit:, absolute_limit: ABSOLUTE_MAX_PASSES
              )
            else
              action = if deadline.expired? || pass_limit >= ABSOLUTE_MAX_PASSES
                :stop
              elsif @convergence_discipline.improving?
                :extend
              else
                :stop
              end
              { action:, reason: deadline.expired? ? :deadline : (pass_limit >= ABSOLUTE_MAX_PASSES ? :absolute_limit : :no_improvement) }
            end
            unless decision[:action] == :extend
              stop_reason = decision[:reason]
              break
            end

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

          return timed_out(pass_limit - 1, pass_limit, budget_seconds) if stop_reason == :deadline
          return terminal(:plateau, "adaptive pass budget exhausted at #{pass_limit}") if pass_limit >= ABSOLUTE_MAX_PASSES

          # The bound was reached without evidence that another pass would help.
          terminal(:plateau, "pass limit (#{pass_limit}) reached")
        end

        # Structural surgery is a post-delivery checkpoint, not the first thing
        # a full-tree run spends its budget on. The first ordinary pass gets to
        # deliver a verified repair; only then does the bounded structural sweep
        # run against freshly observed files.
        def reflect_then_continue(result, files:, target:, max_passes:, budget_seconds:, run_id:)
          state = terminal_state_for(result)
          return result unless %i[done plateau].include?(state)

          reflection = @reflection.call(
            target:, state: state.to_s, files:, history: @convergence_discipline.history,
            changed_paths: @git.respond_to?(:changed_paths) ? @git.changed_paths : [],
            remaining_seconds: @run_journal.remaining_seconds(run_id)
          )
          if reflection.repair?
            @wishlist.record_reflection!(reflection:, state: state.to_s, target:, run_id:)
          elsif reflection.verdict != "KEEP" && reflection.verdict != "INCONCLUSIVE"
            Master::Trace::Dmesg.status("reflect0", "#{reflection.verdict.downcase}, queued for investigation")
          end
          continue_with_wishlist(result, files:, target:, max_passes:, budget_seconds:, run_id:)
        end

        def wishlist_rounds = WISHLIST_MAX_ROUNDS

        def continue_with_wishlist(result, files:, target:, max_passes:, budget_seconds:, run_id:)
          state = terminal_state_for(result)
          return result unless wishlist_rounds.positive? && %i[done plateau].include?(state)

          wishlist_message = @wishlist.call(state: state.to_s, target:, run_id:)
          @bus&.publish("fix_loop:wishlist", state:, target:, message: wishlist_message)

          rounds = 0
          while rounds < wishlist_rounds
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
          return false unless structural_enabled?

          changes = sweep_tree(target, "#{run_id}-structure-checkpoint", phase: :structure_first)
          return false if changes.empty?

          files.replace(@file_collector.collect(target))
          Master::Trace::Dmesg.status("fix0", "structure checkpoint kept #{changes.size}; corpus refreshed")
          @bus&.publish("fix_loop:structure_checkpoint", target:, changes: changes.size)
          run_record = @run_journal.history(limit: RunJournal::MAX_RUNS).find { |row| row["id"] == run_id }
          refresh_fix_plan!(
            target:, files:,
            max_passes: run_record&.fetch("max_passes", max_passes_default) || max_passes_default,
            budget_seconds: run_record&.fetch("budget_seconds", RUN_BUDGET_SECONDS) || RUN_BUDGET_SECONDS,
            run_id:
          )
        end

        def structural_enabled? = ENV["MASTER_FIX_STRUCTURAL"] != "0"

        def structural_target?(target)
          expanded = File.expand_path(target.to_s)
          repo_root = File.basename(@root) == "MASTER" ? File.expand_path("..", @root) : File.expand_path(@root)
          return true if expanded == repo_root
          return false unless MasterPaths::TREES.include?(File.basename(expanded))

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
          over_budget = RunBudget.pass_boundary(pass)
          return over_budget if over_budget

          result = @pass_runner.run_pass(
            files:, target:, pass:, deadline: deadline.at, transaction_id:,
            history: state[:history], seen_snapshots: state[:seen_snapshots],
            recurring_violations: state[:recurring_violations],
            consecutive_clean: state[:consecutive_clean],
            wishlist_proposals:, run_id:
          )
          RunBudget.pass_end(pass)
          @convergence_discipline.note_progress! if @pass_runner.respond_to?(:pass_progress?) && @pass_runner.pass_progress?
          if %i[continue reloading].include?(result.status) && wishlist_proposals.any?
            @wishlist.mark_delivered(
              proposal_ids: wishlist_proposals.map { |proposal| proposal["uid"] },
              run_id:,
            )
          end
          state[:consecutive_clean] = result.consecutive_clean
          structural = structural_repair?(result, files:, target:, state:, run_id:, pass:)
          run_record = @run_journal.history(limit: RunJournal::MAX_RUNS).find { |row| row["id"] == run_id }
          plan_changed = refresh_fix_plan!(
            target:, files:,
            max_passes: run_record&.fetch("max_passes", max_passes_default) || max_passes_default,
            budget_seconds: run_record&.fetch("budget_seconds", RUN_BUDGET_SECONDS) || RUN_BUDGET_SECONDS,
            run_id:
          )
          if plan_changed
            state[:consecutive_clean] = 0
            state[:history].clear
            state[:seen_snapshots].clear
            state[:recurring_violations].clear
            if PASS_ENDINGS[result.status] == :done
              result = @pass_runner.class::PassResult.new(
                status: :continue, consecutive_clean: 0,
                message: "source generation changed; fresh observation required"
              )
            end
          end
          if @convergence_discipline.respond_to?(:checkpoint_state) &&
             @run_journal.respond_to?(:save_convergence_state)
            @run_journal.save_convergence_state(
              run_id,
              @convergence_discipline.checkpoint_state,
              pass_state: durable_pass_state(state),
            )
          end
          return if structural

          @run_journal.pass_finish(run_id, pass, status: result.status, message: result.message)
          ending = PASS_ENDINGS[result.status]
          return terminal(ending, result.message) if ending

          result.status == :plateau ? :break : nil
        end

        # Err, not ok. A run that stopped because the clock ran out did not
        # finish fixing, and saying "ok" here is how the 2026-07-31 check
        # reported a green MASTER phase whose /fix had completed exactly one
        # pass: bin/cli exited 0, bin/check --ladder saw success, and the /scan on
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
          return false unless structural_enabled?
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
      end
    end
  end
end
