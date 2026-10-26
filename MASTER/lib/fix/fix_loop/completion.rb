# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      # Completion owns terminalization side effects: durable journal state,
      # mission state, receipts and the terminal event. OutcomePolicy remains
      # the pure decision core; this module applies that decision to runtime state.
      module Completion
        private

        # DONE needs complete evidence, not just a clean scanner result. A run
        # with skipped files, failed stages, or an unmeasured Law/stream/surface
        # matrix must report the missing proof instead of claiming completion.
        def blocked_by_gaps(result)
          matrix_unmeasured = @pass_runner &&
            @pass_runner.respond_to?(:assessment_matrix_status) &&
            @pass_runner.assessment_matrix_status == :not_measured
          gapped = @pass_runner&.gaps? || uninspectable.any? || matrix_unmeasured
          return result unless gapped && result.ok? && terminal_state_for(result) == :done

          gaps = @pass_runner ? @pass_runner.gaps : { uninspected: {}, stage_failures: {} }
          parts = uninspectable.empty? ? [] : ["uninspectable inputs remain: #{uninspectable_detail}"]

          unless gaps[:uninspected].empty?
            named = gaps[:uninspected].keys.first(3).join(", ")
            parts << "#{gaps[:uninspected].size} file(s) not scanned (#{named})"
          end
          semantic_gaps = gaps.fetch(:semantic_inconclusive, {})
          unless semantic_gaps.empty?
            named = semantic_gaps.keys.first(3).join(", ")
            parts << "#{semantic_gaps.size} file(s) with inconclusive semantic assessment (#{named})"
          end
          pending = gaps.fetch(:semantic_pending, {})
          unless pending.empty?
            parts << "#{pending.size} file(s) awaiting a semantic read (#{pending.keys.first(3).join(", ")})"
          end
          gaps[:stage_failures].each { |stage, rows| parts << "#{stage} stage failed #{rows.size}x, last #{rows.last}" }
          parts << "law/stream/surface assessment matrix not measured; DONE withheld" if matrix_unmeasured
          Master::Trace::Dmesg.status("fix0", "finished with gaps: #{parts.join("; ")}"[0, 220])
          terminal(:blocked, "finished with gaps, #{parts.join("; ")}")
        end

        # A pass cut short by a hot reload attempted nothing and is not a completed run; the
        # restarted process carries the work on.
        def run_end_reason(result)
          return "reloading: origin/main changed" if CodeWatch.requested?

          state = terminal_state_for(result)
          return "completed" if state == :done

          "#{state}: #{result.to_s[0, 80]}"
        end

        def finish_run(result, target, run_id, mission: nil, requested: false)
          result = blocked_by_gaps(result)
          RunBudget.finish_run(reason: run_end_reason(result))
          state = terminal_state_for(result)
          @last_terminal_state = state
          convergence_evidence = @convergence_discipline.receipt if @convergence_discipline.respond_to?(:receipt)
          evidence = convergence_evidence&.dup || {}
          plan_evidence = @fix_plan&.to_h&.slice(
            "version", "digest", "identity_digest", "scope_digest", "source_digest",
            "law_digest", "law_source_digest", "authority_digest", "toolchain_digest",
            "exclusion_digest", "adapter_digest", "eligible_files", "deadline_at"
          )
          evidence[:fix_plan] = plan_evidence if plan_evidence
          run_record = @run_journal.history(limit: RunJournal::MAX_RUNS).find { |row| row["id"] == run_id }
          plan_generation = Array(run_record && run_record["plan_generations"]).last&.fetch("generation", nil)
          evidence[:fix_plan_generation] = plan_generation unless plan_generation.nil?
          @run_journal.terminal(run_id, state, message: result.to_s, evidence:)

          if %i[cancelled unknown_outcome recovery_failed].include?(state)
            # An explicit stop or ambiguous external outcome outranks a concurrent
            # wake request; otherwise the steward could replay work the operator
            # cancelled or the system could not prove safe to repeat.
            mission&.finish!(state: state.to_s, summary: result.to_s)
          elsif mission&.requeue_if_requested!
            @bus&.publish("fix_loop:mission_requeued", run_id:, state:, reason: "wake received during attempt")
          elsif state == :done
            mission&.finish!(state: "completed", summary: result.to_s)
          elsif %i[human_decision blocked].include?(state)
            mission&.block!(reason: result.to_s)
          else
            mission&.defer!(reason: "attempt #{state}: #{result.to_s}")
          end

          target_label = fix_target_label(target)
          outcome = { state:, message: result.to_s, task_id: run_id, capability: "code_repair", target: target_label, run_id: }
          if plan_evidence
            outcome[:plan_digest] = plan_evidence["digest"]
            outcome[:plan_generation] = plan_generation unless plan_generation.nil?
            outcome[:source_digest] = plan_evidence["source_digest"]
          end
          outcome[:outcome_receipt] = write_outcome_receipt(
            run_id:, target: target_label, state:, result:, convergence: convergence_evidence
          )
          outcome[:ok] = MEASURED_REPAIR_OUTCOMES.fetch(state) if MEASURED_REPAIR_OUTCOMES.key?(state)
          @bus&.publish("fix_loop:terminal", **outcome)

          result
        end
      end
    end
  end
end
