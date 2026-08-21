# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      # Convergence/cycle threshold readers pulled from axioms + workflow
      # limits — kept separate from FixLoop's run/background-lifecycle
      # responsibilities so NO_GOD_CLASS's public-method count reflects those
      # two concerns on their own.
      module ConvergenceConfig
        def convergence_cfg = @convergence ||= (@axioms&.thresholds&.[]("convergence") || {})

        def max_passes_default
          configured = convergence_cfg["max_iterations"] || MAX_PASSES
          mode_cap = begin
            Master::Ground::ModePosture.current(root: @root)[:max_fix_passes]
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "ConvergenceConfig.mode_cap")
            nil
          end
          [mode_cap, configured].compact.map(&:to_i).min
        end
        def clean_runs_required    = convergence_cfg["consecutive_clean_runs_required"]          || CLEAN_RUNS
        def plateau_window         = convergence_cfg["stagnant_threshold"]                       || PLATEAU_WINDOW
        def max_cycles_default     = workflow_cfg.dig("autoloop", "max_cycles")                 || max_passes_default
        def startup_delay_default  = workflow_cfg.dig("autoloop", "startup_delay")              || STARTUP_DELAY
        def idle_sleep_default     = workflow_cfg.dig("autoloop", "idle_sleep")                 || IDLE_SLEEP
      end
    end
  end
end
