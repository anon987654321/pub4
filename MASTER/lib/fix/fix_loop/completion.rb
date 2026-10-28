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
          matrix_status = @pass_runner&.assessment_matrix_status || :not_measured
          matrix_unmeasured = matrix_status == :not_measured
          # Unknown/missing states fail closed too; only an explicitly complete,
          # generation-current matrix can authorize DONE.
          matrix_incomplete = matrix_status != :complete && !matrix_unmeasured
          matrix_gapped = matrix_unmeasured || matrix_incomplete
          gapped = @pass_runner&.gaps? || uninspectable.any? || matrix_gapped
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
          if matrix_gapped
            summary = @pass_runner.respond_to?(:assessment_matrix_summary) ? @pass_runner.assessment_matrix_summary : {}
            if matrix_unmeasured
              parts << "law/stream/surface assessment matrix not measured; DONE withheld"
            else
              parts << "law/stream/surface assessment matrix incomplete " \
                "(expected=#{summary[:expected_cells] || summary["expected_cells"]}, " \
                "recorded=#{summary[:recorded_cells] || summary["recorded_cells"]}, " \
                "unassessed=#{summary[:unassessed_cells] || summary["unassessed_cells"]}, " \
                "inconclusive=#{summary[:inconclusive_cells] || summary["inconclusive_cells"]}, " \
                "findings=#{summary[:finding_cells] || summary["finding_cells"]}); DONE withheld"
            end
          end
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
          assessment_receipt = persist_assessment_receipt(run_id:, target:)
          plan_manifest = @fix_plan&.to_h
          provenance_values = if plan_manifest.is_a?(Hash)
                                {
                                  "plan_digest" => @fix_plan.digest,
                                  "identity_digest" => plan_manifest["identity_digest"],
                                  "scope_digest" => plan_manifest["scope_digest"],
                                  "source_digest" => plan_manifest["source_digest"],
                                  "law_digest" => plan_manifest["law_digest"],
                                  "law_source_digest" => plan_manifest["law_source_digest"],
                                  "authority_digest" => plan_manifest["authority_digest"],
                                  "toolchain_digest" => plan_manifest["toolchain_digest"],
                                  "exclusion_digest" => plan_manifest["exclusion_digest"],
                                  "adapter_digest" => plan_manifest["adapter_digest"],
                                }
                              else
                                {}
                              end
          provenance_matches = !provenance_values.empty? &&
            provenance_values.all? { |key, value| !value.to_s.empty? && assessment_receipt[key] == value }
          proof_ready = assessment_receipt["status"] == "persisted" &&
            assessment_receipt["readback_verified"] == true &&
            assessment_receipt["matrix_status"] == "complete" &&
            assessment_receipt["verification"] == "verified" &&
            provenance_matches
          if terminal_state_for(result) == :done && !proof_ready
            result = terminal(
              :blocked,
              "four-stream assessment receipt is not complete, verified and plan-bound " \
                "(artifact=#{assessment_receipt["status"]}, matrix=#{assessment_receipt["matrix_status"]}, " \
                "verification=#{assessment_receipt["verification"] || "unavailable"}, " \
                "provenance=#{provenance_matches ? "matched" : "mismatch"}); DONE withheld",
            )
          end
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
          matrix_evidence = if @pass_runner&.respond_to?(:assessment_matrix_evidence)
                              @pass_runner.assessment_matrix_evidence
                            else
                              { status: "not_measured", reason: "assessment matrix adapter unavailable" }
                            end
          matrix_evidence = matrix_evidence.dup
          matrix_evidence[:ledger_receipt] = assessment_receipt
          evidence[:assessment_matrix] = matrix_evidence
          evidence[:assessment_ledger_receipt] = assessment_receipt
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
          outcome[:assessment_matrix] = matrix_evidence
          outcome[:outcome_receipt] = write_outcome_receipt(
            run_id:, target: target_label, state:, result:, convergence: convergence_evidence,
          )
          outcome[:ok] = MEASURED_REPAIR_OUTCOMES.fetch(state) if MEASURED_REPAIR_OUTCOMES.key?(state)
          @bus&.publish("fix_loop:terminal", **outcome)

          result
        end

        def persist_assessment_receipt(run_id:, target:)
          report = if @pass_runner&.respond_to?(:assessment_matrix_artifact)
                     @pass_runner.assessment_matrix_artifact
                   else
                     { schema_version: 1, status: "not_measured", reason: "assessment matrix artifact adapter unavailable" }
                   end
          receipt = @run_journal.persist_assessment_report(run_id, target:, report:)
          verification = @run_journal.verify_assessment_report(run_id)
          raise "assessment artifact verification failed: #{verification["status"]}" unless verification["status"] == "verified"

          receipt.merge("verification" => "verified")
        rescue StandardError => e
          @bus&.publish(
            "fix_loop:assessment_receipt_failed",
            run_id:, error_class: e.class.name, message: e.message.to_s[0, 180],
          )
          {
            "status" => "persistence_failed",
            "error_class" => e.class.name,
            "message" => e.message.to_s[0, 180],
          }
        end
      end
    end
  end
end
