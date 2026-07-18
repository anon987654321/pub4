# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      # Background-thread lifecycle (start/stop/halt) — a separate concern
      # from the single-pass run/preview responsibility that stays in
      # fix_loop.rb proper.
      module BackgroundRunner
        def run_forever(target = @root, max_cycles: max_cycles_default, startup_delay: startup_delay_default,
                        idle_sleep: idle_sleep_default, cooldown_sleep: idle_sleep_default)
          sleep startup_delay
          cycles = 0
          while cycles < max_cycles
            break if halted?
            cycles += 1
            begin
              run(target)
              break if halted?
              @bus&.publish("fix_loop:idle", sleep: idle_sleep, cycle: cycles, max_cycles:)
              sleep idle_sleep
            rescue StandardError => e
              @bus&.publish("fix_loop:error", error: e.message, cycle: cycles, max_cycles:)
              sleep cooldown_sleep
            end
          end
          @bus&.publish("fix_loop:max_cycles", cycles:, max_cycles:) unless halted?
        end

        def start_background!(target = @root)
          return Result.err("fix_loop already running") if @bg_thread&.alive?
          @halted = false
          @halt_reason = nil
          @bg_thread = Thread.new { run_forever(target) }
          @bg_thread.abort_on_exception = false
          @bus&.publish("fix_loop:background_start", target:)
          Result.ok("fix_loop background started")
        end

        def stop_background!
          return Result.err("fix_loop not running") unless @bg_thread&.alive?
          @bg_thread.kill
          @bg_thread = nil
          @bus&.publish("fix_loop:background_stop")
          Result.ok("fix_loop background stopped")
        end

        def background_alive? = @bg_thread&.alive? || false

        def halt!(reason: "self_violation")
          @halted = true
          @halt_reason = reason
          @bg_thread&.kill if @bg_thread&.alive?
          @bg_thread = nil
          @bus&.publish("fix_loop:halt", reason:)
          Result.ok("fix_loop halted: #{reason}")
        end

        def halted? = @halted
      end
    end
  end
end
