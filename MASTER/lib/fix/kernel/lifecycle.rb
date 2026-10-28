# frozen_string_literal: true

require "socket"

# Run-level orchestration and adapter factories for the canonical repair Kernel.
module Master
  module Fix
    class Kernel
      # The public FixLoop constant is an adapter name for this canonical
      # Kernel-owned convergence coordinator. The implementation is loaded only
      # after this identity exists, so every nested pass module opens the same class.
      class ConvergenceAdapter
        # Keep the public FixLoop constant lazy: read-only Kernel users must not
        # boot the full pass graph, but any real constructor or nested constant
        # access must load the implementation before dispatch.
        def self.new(...)
          require_relative "../fix_loop"
          super
        end

        def self.const_missing(name)
          require_relative "../fix_loop"
          return const_get(name, false) if const_defined?(name, false)

          super
        end
      end

      class RepairAdapter; end unless const_defined?(:RepairAdapter, false)

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
          require_relative "../fix_loop"
          Kernel::ConvergenceAdapter.new(**options, kernel: self)
        end

        def build_repair_loop(**options)
          require_relative "repair_adapter"
          Kernel::RepairAdapter.new(**options, kernel: self)
        end

        # Execute the convergence adapter under the single Kernel-owned lock and
        # lifecycle boundary. The adapter still owns the per-pass implementation,
        # but only Kernel starts, terminalizes, and correlates the overall run.
        def run_fix_loop(adapter, target:, max_passes:, budget_seconds:, incremental:, requested:, cancellation: nil)
          @execution_mutex.synchronize do
            coordinator_run_id = nil
            previous_cancellation = adapter.instance_variable_get(:@cancellation)
            previous_run_id = @current_run_id
            begin
              adapter.instance_variable_set(:@cancellation, cancellation)
              cancellation.activate! if cancellation&.respond_to?(:activate!)
              coordinator_run_id = begin_coordinated_run(target:, max_passes:, budget_seconds:, requested:)
              @current_run_id = coordinator_run_id
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
              @current_run_id = previous_run_id
              adapter.instance_variable_set(:@cancellation, previous_cancellation)
            end
          end
        end

        # Hash-chained operational evidence around the legacy convergence adapter.
        # Detailed pass and recovery state still lives in lifecycle_journal.
        def begin_coordinated_run(target:, max_passes:, budget_seconds:, requested:)
          reconcile_coordinated_runs!
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
            budget_seconds: Integer(budget_seconds), requested: requested == true,
            host: Socket.gethostname, pid: Process.pid
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
          }, run_id: @current_run_id)
        end

        private

        # A writer that died between start and terminal left an open lifecycle
        # receipt. Reconcile only same-host processes that are known gone; never
        # turn a possibly live peer into an apparent completed or failed run.
        def reconcile_coordinated_runs!
          events = verify_log!
          terminal_ids = events.each_with_object({}) do |row, seen|
            seen[row["run_id"]] = true if row["kind"] == "coordinator_terminal" && row["run_id"]
          end
          events.each do |row|
            next unless row["kind"] == "coordinator_started"

            run_id = row["run_id"]
            next if run_id.nil? || terminal_ids[run_id]

            payload = row["payload"].is_a?(Hash) ? row["payload"] : {}
            next unless payload["host"].to_s == Socket.gethostname

            pid = Integer(payload["pid"]) rescue nil
            # A PID owned by this process may belong to another live Kernel
            # instance (for example, a foreground command beside the watcher).
            # Keep it open; this reconciliation is deliberately cross-process.
            next unless pid && pid.positive?
            next if pid == Process.pid || coordinator_process_alive?(pid)

            append_event("coordinator_terminal", {
              state: "unknown_outcome",
              recovered: true,
              reason: "coordinator process ended without a terminal receipt",
              previous_process_id: pid,
            }, run_id:)
            terminal_ids[run_id] = true
          end
          true
        end

        def coordinator_process_alive?(pid)
          Process.kill(0, pid)
          true
        rescue Errno::ESRCH, RangeError, TypeError, ArgumentError
          false
        rescue Errno::EPERM
          true
        end
      end
    end
    FixLoop = Kernel::ConvergenceAdapter unless const_defined?(:FixLoop, false)
    RunJournal = Kernel::LifecycleJournal unless const_defined?(:RunJournal, false)
  end
end