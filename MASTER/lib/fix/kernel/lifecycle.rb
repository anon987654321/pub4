# frozen_string_literal: true

# Run-level orchestration and adapter factories for the canonical repair Kernel.
module Master
  module Fix
    class Kernel
      module Lifecycle
        # The Kernel owns /fix lifecycle coordination. RunJournal is currently its
        # durable metadata adapter; no caller should construct a second journal for
        # the same coordinator. Keeping it behind this accessor makes the migration
        # incremental without changing the persisted format or recovery contract.
        def lifecycle_journal
          @lifecycle_mutex.synchronize do
            @lifecycle_journal ||= LifecycleJournal.new(root: @root, bus: @bus)
          end
        end

        alias run_journal lifecycle_journal

        # Production factories make Kernel the shared owner while the old loop
        # classes remain behavior-preserving adapters until their parity gates pass.
        def build_fix_loop(**options)
          require_relative "fix_loop" unless defined?(FixLoop)
          FixLoop.new(**options, kernel: self)
        end

        def build_repair_loop(**options)
          require_relative "repair_adapter" unless defined?(Kernel::RepairAdapter)
          Kernel::RepairAdapter.new(**options, kernel: self)
        end

        # Execute the convergence adapter under the single Kernel-owned lock and
        # lifecycle boundary. The adapter still owns the per-pass implementation,
        # but only Kernel starts, terminalizes, and correlates the overall run.
        def run_fix_loop(adapter, target:, max_passes:, budget_seconds:, incremental:, requested:, cancellation: nil)
          @execution_mutex.synchronize do
            coordinator_run_id = nil
            previous_cancellation = adapter.instance_variable_get(:@cancellation)
            previous_run_id = Fiber[:master_fix_kernel_run_id]
            begin
              adapter.instance_variable_set(:@cancellation, cancellation)
              cancellation.activate! if cancellation&.respond_to?(:activate!)
              coordinator_run_id = begin_coordinated_run(target:, max_passes:, budget_seconds:, requested:)
              Fiber[:master_fix_kernel_run_id] = coordinator_run_id
              result = adapter.run_unlocked(
                target, max_passes:, budget_seconds:, incremental:, requested:
              )
              state = adapter.last_terminal_state || OutcomePolicy.terminal_state(result) || :unknown_outcome
              finish_coordinated_run(run_id: coordinator_run_id, state:, outcome: result)
              result
            rescue StandardError => error
              if coordinator_run_id
                begin
                  finish_coordinated_run(run_id: coordinator_run_id, state: :unknown_outcome, error:)
                rescue StandardError => journal_error
                  Master::Ground::Swallow.log(
                    journal_error, context: "fix_kernel.coordinator_terminal", event_bus: @bus
                  )
                end
              end
              raise
            ensure
              Fiber[:master_fix_kernel_run_id] = previous_run_id
              adapter.instance_variable_set(:@cancellation, previous_cancellation)
            end
          end
        end

        # Hash-chained operational evidence around the legacy convergence adapter.
        # Detailed pass and recovery state still lives in lifecycle_journal.
        def begin_coordinated_run(target:, max_passes:, budget_seconds:, requested:)
          run_id = SecureRandom.hex(12)
          expanded = File.expand_path(target.to_s, @root)
          target_label = if expanded == @workspace_root
                           "."
                         elsif expanded.start_with?(@workspace_root + File::SEPARATOR)
                           expanded.delete_prefix(@workspace_root + File::SEPARATOR)
                         else
                           "(external target)"
                         end
          append_event("coordinator_started", {
            actor: @actor, target: target_label, max_passes: Integer(max_passes),
            budget_seconds: Integer(budget_seconds), requested: requested == true
          }, run_id:)
          run_id
        end

        def finish_coordinated_run(run_id:, state:, outcome: nil, error: nil)
          payload = { state: state.to_s }
          if outcome
            payload[:result] = outcome.respond_to?(:err?) && outcome.err? ? "error" : "ok"
            payload[:category] = outcome.category.to_s if outcome.respond_to?(:category) && outcome.err?
          end
          payload[:error_class] = error.class.name if error
          append_event("coordinator_terminal", payload, run_id:)
        end

        # Bounded repair summary; no prompt, source text, or model output enters the
        # coordinator ledger. A failed write remains an error rather than a false
        # successful receipt.
        def record_repair_outcome(law:, status:, fixed:, breakdown:)
          counts = (breakdown || {}).to_h.to_h { |key, value| [key.to_s, Integer(value)] }
          append_event("repair_pass", {
            law: law.to_s, status: status.to_s, fixed: Integer(fixed), breakdown: counts
          }, run_id: Fiber[:master_fix_kernel_run_id])
        end
      end
    end
  end
end
