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
          require_relative "convergence_adapter"
          super
        end

        def self.const_missing(name)
          require_relative "convergence_adapter"
          return const_get(name, false) if const_defined?(name, false)

          super
        end
      end

      class RepairAdapter; end unless const_defined?(:RepairAdapter, false)

      module Lifecycle
        # Kernel owns the durable lifecycle-journal implementation. The historical
        # RunJournal constant remains an alias, and every production writer enters
        # through this accessor so a run has one journal owner and one on-disk format.
        def lifecycle_journal
          # Installing the historical alias here avoids consuming a pending
          # Zeitwerk autoload while ensuring existing callers see one class.
          require_relative "../run_journal"
          @lifecycle_mutex.synchronize do
            @lifecycle_journal ||= LifecycleJournal.new(root: @root, bus: @bus)
          end
        end

        alias run_journal lifecycle_journal

        # Production factories make Kernel the shared owner while the old loop
        # classes remain behavior-preserving adapters until their parity gates pass.
        def build_fix_loop(**options)
          require_relative "convergence_adapter"
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
            attempt_id = SecureRandom.hex(12)
            previous_cancellation = adapter.instance_variable_get(:@cancellation)
            previous_run_id = @current_run_id
            previous_attempt_id = @current_attempt_id
            begin
              @current_run_id = nil
              @current_attempt_id = attempt_id
              adapter.instance_variable_set(:@cancellation, cancellation)
              cancellation.activate! if cancellation&.respond_to?(:activate!)
              reconcile_coordinated_runs!
              result = adapter.run_unlocked(
                target, max_passes:, budget_seconds:, incremental:, requested:
              )

              # A normal run binds its durable RunJournal ID from inside FixLoop
              # before the first repair pass. Short preflight exits still receive
              # a truthful coordinator receipt without inventing a second active ID.
              coordinator_run_id = @current_run_id
              unless coordinator_run_id
                coordinator_run_id = begin_coordinated_run(
                  target:, max_passes:, budget_seconds:, requested:,
                  run_id: SecureRandom.hex(12), attempt_id: @current_attempt_id
                )
                @current_run_id = coordinator_run_id
              end
              current_attempt_id = @current_attempt_id || attempt_id
              state = adapter.last_terminal_state || OutcomePolicy.terminal_state(result) || :unknown_outcome
              finish_coordinated_run(
                run_id: coordinator_run_id, attempt_id: current_attempt_id, state:, outcome: result
              )
              result
            rescue StandardError => error
              coordinator_run_id ||= @current_run_id
              current_attempt_id = @current_attempt_id || attempt_id
              begin
                unless coordinator_run_id
                  coordinator_run_id = begin_coordinated_run(
                    target:, max_passes:, budget_seconds:, requested:,
                    run_id: SecureRandom.hex(12), attempt_id: current_attempt_id
                  )
                  @current_run_id = coordinator_run_id
                end
                finish_coordinated_run(
                  run_id: coordinator_run_id, attempt_id: current_attempt_id,
                  state: :unknown_outcome, error:
                )
              rescue StandardError => receipt_error
                Master::Ground::Swallow.log(
                  receipt_error, context: "fix_kernel.coordinator_terminal", event_bus: @bus
                )
              end
              raise
            ensure
              @current_run_id = previous_run_id
              @current_attempt_id = previous_attempt_id
              adapter.instance_variable_set(:@cancellation, previous_cancellation)
            end
          end
        end

        # Link the receipt lifecycle to the durable RunJournal identity as soon
        # as it exists, before the pass runner can mutate source files.
        def bind_fix_run(adapter:, run_id:, target:, max_passes:, budget_seconds:, requested:)
          value = run_id.to_s
          raise ArgumentError, "Fix run ID must be present" if value.empty?
          return value if @current_run_id == value

          if @current_run_id
            previous_attempt = @current_attempt_id
            previous_state = adapter.respond_to?(:last_terminal_state) && adapter.last_terminal_state
            finish_coordinated_run(
              run_id: @current_run_id, attempt_id: previous_attempt,
              state: previous_state || :unknown_outcome
            )
            # A single operator invocation can close an expired journal row and
            # open a fresh one; each segment needs its own attempt receipt.
            @current_attempt_id = SecureRandom.hex(12)
          else
            @current_attempt_id ||= SecureRandom.hex(12)
          end

          begin_coordinated_run(
            target:, max_passes:, budget_seconds:, requested:,
            run_id: value, attempt_id: @current_attempt_id
          )
          @current_run_id = value
        end

        # Link the separate durable Mission objective to the journal run identity.
        # This is a metadata-only receipt; it never implies that source changes landed.
        def link_fix_mission(mission_id:, run_id: @current_run_id)
          value = run_id.to_s
          raise ArgumentError, "Mission link requires the active Fix run ID" if value.empty?
          raise "Mission link belongs to another Fix run" unless value == @current_run_id

          append_event("coordinator_mission_link", {
            mission_id: mission_id.to_s, attempt_id: @current_attempt_id
          }, run_id: value)
        end

        # Hash-chained operational evidence around the legacy convergence adapter.
        # Detailed pass and recovery state still lives in lifecycle_journal.
        def begin_coordinated_run(target:, max_passes:, budget_seconds:, requested:,
                                  run_id: nil, attempt_id: nil)
          reconcile_coordinated_runs!
          run_id ||= SecureRandom.hex(12)
          attempt_id ||= SecureRandom.hex(12)
          @current_attempt_id = attempt_id
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
            host: Socket.gethostname, pid: Process.pid, process_token: kernel_process_token,
            attempt_id:
          }, run_id:)
          run_id
        end

        def finish_coordinated_run(run_id:, state:, outcome: nil, error: nil, attempt_id: nil)
          attempt_id ||= @current_attempt_id
          if attempt_id
            existing = verify_log!.find do |row|
              next false unless row["kind"] == "coordinator_terminal" && row["run_id"] == run_id

              prior_payload = row["payload"].is_a?(Hash) ? row["payload"] : {}
              prior_payload["attempt_id"] == attempt_id
            end
            return existing if existing
          end
          payload = { state: state.to_s }
          payload[:attempt_id] = attempt_id if attempt_id
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
            law: law.to_s, status: status.to_s, fixed: Integer(fixed), breakdown: counts,
            attempt_id: @current_attempt_id
          }, run_id: @current_run_id)
        end

        private

        # A writer that died between start and terminal left an open lifecycle
        # receipt. Reconcile only same-host processes that are known gone; never
        # turn a possibly live peer into an apparent completed or failed run.
        def reconcile_coordinated_runs!
          events = verify_log!
          terminal_ids = events.each_with_object({}) do |row, seen|
            next unless row["kind"] == "coordinator_terminal" && row["run_id"]

            terminal_payload = row["payload"].is_a?(Hash) ? row["payload"] : {}
            attempt_key = terminal_payload["attempt_id"].to_s
            seen[attempt_key.empty? ? row["run_id"] : attempt_key] = true
          end
          events.each do |row|
            next unless row["kind"] == "coordinator_started"

            run_id = row["run_id"]
            next if run_id.nil?

            payload = row["payload"].is_a?(Hash) ? row["payload"] : {}
            attempt_key = payload["attempt_id"].to_s
            attempt_key = run_id if attempt_key.empty?
            next if terminal_ids[attempt_key]
            next unless payload["host"].to_s == Socket.gethostname

            pid = Integer(payload["pid"]) rescue nil
            # A PID may have been reused after the old process died. A process-wide
            # random token distinguishes that case from another live Kernel instance
            # in this process; older receipts without a token remain conservative.
            next unless pid && pid.positive?
            if pid == Process.pid
              token = payload["process_token"].to_s
              next if token.empty? || token == kernel_process_token
            elsif coordinator_process_alive?(pid)
              next
            end

            append_event("coordinator_terminal", {
              state: "unknown_outcome",
              recovered: true,
              reason: "coordinator process ended without a terminal receipt",
              previous_process_id: pid,
              attempt_id: attempt_key,
            }, run_id:)
            terminal_ids[attempt_key] = true
          end
          true
        end

        def kernel_process_token
          self.class.instance_variable_get(:@process_token) ||
            self.class.instance_variable_set(:@process_token, SecureRandom.hex(12))
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

  end
end
