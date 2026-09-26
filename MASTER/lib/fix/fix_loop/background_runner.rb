# frozen_string_literal: true

require_relative "../supervisor"

module Master
  module Fix
    class FixLoop
      # Lifecycle wrapper around the durable Supervisor. The FixLoop itself stays
      # finite; this layer keeps the objective alive by scheduling another bounded
      # attempt whenever its persisted mission says work is due.
      module BackgroundRunner
        def start_background!(target = @root)
          return Result.err("fix_loop already running") if @bg_thread&.alive?
          @halted = false
          @halt_reason = nil
          @bg_mutex ||= Mutex.new
          @bg_condition ||= ConditionVariable.new
          @bg_target = target

          prepared = prepare_background_mission(target)
          return prepared unless prepared.ok?

          @supervisor = Supervisor.new(root: @root, target:, fix_loop: self, bus: @bus,
                                       wake_mutex: @bg_mutex, wake_condition: @bg_condition)
          @bg_thread = Thread.new { @supervisor.run_forever }
          @bg_thread.abort_on_exception = false
          @bus&.publish("fix_loop:background_start", target:)
          Result.ok("fix_loop background started")
        end

        def stop_background!
          return Result.err("fix_loop not running") unless @bg_thread&.alive?

          @supervisor&.stop!
          @bg_thread.join(2)
          @bg_thread.kill if @bg_thread&.alive?
          @bg_thread = nil
          @supervisor = nil
          @bus&.publish("fix_loop:background_stop")
          Result.ok("fix_loop background stopped")
        end

        def background_alive? = @bg_thread&.alive? || false

        # File watchers, model recovery and external events use this as a wake
        # signal. They never execute FixLoop directly while the durable supervisor
        # is running.
        def wake_background!(reason: "external_event", path: nil)
          target = @bg_target || @root
          prepared = prepare_background_mission(target)
          return prepared unless prepared.ok?

          mission = Mission.new(root: @root, bus: @bus)
          mission.wake!(reason: path ? "#{reason}: #{relative_target(path)}" : reason)
          @supervisor&.wake!(reason:)
          Result.ok("fix_loop wake requested")
        rescue StandardError => e
          @bus&.publish("fix_loop:wake_error", error: "#{e.class}: #{e.message}")
          Result.err("fix_loop wake: #{e.message}", category: :infrastructure)
        end

        def halt!(reason: "self_violation")
          @halted = true
          @halt_reason = reason
          @supervisor&.stop!
          @bg_thread&.kill if @bg_thread&.alive?
          @bg_thread = nil
          @supervisor = nil
          Mission.block_current(root: @root, reason: reason)
          @bus&.publish("fix_loop:halt", reason:)
          Result.ok("fix_loop halted: #{reason}")
        end

        def halted? = @halted

        # Kept as the compatibility entry point for callers/tests that exercised
        # the old loop directly. max_cycles/startup_delay/idle_sleep are obsolete:
        # the durable mission, its next_wake_at and the supervisor now own lifetime.
        def run_forever(target = @root, **_legacy)
          @bg_target = target
          @bg_mutex ||= Mutex.new
          @bg_condition ||= ConditionVariable.new
          @supervisor ||= Supervisor.new(root: @root, target:, fix_loop: self, bus: @bus,
                                         wake_mutex: @bg_mutex, wake_condition: @bg_condition)
          prepare_background_mission(target)
          @supervisor.run_forever
        end

        private

        def prepare_background_mission(target)
          current = Mission.current(root: @root)
          relative = relative_target(target)
          if current && current["scope"].to_s == relative && current["state"].to_s == "blocked"
            return Result.err("fix_loop mission blocked: #{current["wake_reason"]}")
          end

          mission = Mission.new(root: @root, bus: @bus)
          mission.ensure_queued!(
            goal: "fix #{relative}",
            scope: target,
            model: @agent.respond_to?(:model) ? @agent.model : ENV["MASTER_MODEL"],
            effort: ENV.fetch("MASTER_EFFORT", "high"),
            plan: Ground::ActivePlan.read(@root),
          )
          Result.ok(mission.record)
        rescue StandardError => e
          @bus&.publish("fix_loop:mission_prepare_error", error: "#{e.class}: #{e.message}")
          Result.err("fix_loop mission prepare: #{e.message}", category: :infrastructure)
        end

        def relative_target(path)
          full = File.expand_path(path)
          root = File.expand_path(@root)
          return path.to_s unless full == root || full.start_with?(root + File::SEPARATOR)

          full.delete_prefix(root + File::SEPARATOR)
        end
      end
    end
  end
end