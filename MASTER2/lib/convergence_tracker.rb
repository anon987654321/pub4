# frozen_string_literal: true

module MASTER
  # Tracks per-iteration convergence metrics during self-refactoring.
  # Detects diminishing returns and oscillation so the loop halts
  # instead of churning forever.
  module ConvergenceTracker
    module_function

    def reset!
      @history = []
    end

    def history
      @history ||= []
    end

    # Record one iteration's metrics
    def record_iteration(violations:, fixed:, deferred:)
      prev = history.last
      prev_count = prev ? prev[:violations] : violations + fixed
      delta = prev_count - violations
      rate = (violations + fixed).zero? ? 0.0 : (fixed.to_f / (violations + fixed))

      entry = {
        iteration: history.size + 1,
        violations: violations,
        violation_delta: delta,
        fixed: fixed,
        deferred: deferred,
        autofix_success_rate: rate.round(3),
      }
      history << entry
      entry
    end

    # Should the convergence loop stop?
    def should_halt?
      return false if history.size < 2

      # Halt if no progress for 2 consecutive iterations
      last_two = history.last(2)
      stalled  = last_two.all? { |h| h[:violation_delta] == 0 }
      if stalled
        record_friction(:wasted_iteration, iterations: history.size, last: last_two.last)
        return true
      end

      # Halt if autofix success rate dropped below 10%
      latest = history.last
      return true if latest[:autofix_success_rate] < 0.1

      # Halt if only deferred debt remains (nothing left to fix)
      return true if latest[:violations].zero?

      false
    end

    # dmesg-style summary of current state
    def summary
      return "converge0: no iterations recorded" if history.empty?

      h = history.last
      prev_violations = history.size > 1 ? history[-2][:violations] : "?"
      oscillating = detect_oscillation

      "converge0: iter=#{h[:iteration]} " \
        "violations=#{prev_violations}->#{h[:violations]} " \
        "fixed=#{h[:fixed]} " \
        "deferred=#{h[:deferred]} " \
        "oscillating=#{oscillating}"
    end

    # Detect if violations are bouncing up and down
    def detect_oscillation
      return 0 if history.size < 3

      deltas = history.last(3).map { |h| h[:violation_delta] }
      signs = deltas.map { |d| d <=> 0 }
      # Oscillation: positive, negative, positive (or vice versa)
      signs[0] != 0 && signs[0] == -signs[1] && signs[1] == -signs[2] ? 1 : 0
    end

    def record_friction(pattern_id, context = {})
      return unless defined?(MASTER::Friction::FrictionRecorder)

      MASTER::Friction::FrictionRecorder.record(pattern_id, context)
    rescue StandardError
      # never let friction recording break the main loop
    end
  end
end
