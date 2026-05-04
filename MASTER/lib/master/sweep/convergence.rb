# frozen_string_literal: true

module Master
  class Sweep
    # Per-cycle metrics tracking and early-stop logic for sweep loops.
    # Detects stall, low success rate, and sign-reversal oscillation.
    module Convergence
      LOW_SUCCESS_RATE = 0.10

      private

      def init_cycle_log
        @cycle_log = []
      end

      # Record one cycle's metrics. Returns the entry for bus publishing.
      def record_cycle(violations:, fixed:, deferred:)
        prev  = @cycle_log.last
        delta = prev ? (prev[:violations] - violations) : fixed
        total = violations + fixed
        rate  = total.zero? ? 0.0 : (fixed.to_f / total).round(3)
        entry = { violations:, fixed:, deferred:, delta:, rate: }
        @cycle_log << entry
        entry
      end

      # Unified early-stop: stall, low success rate, oscillation, or done.
      def should_halt_early?
        return false if @cycle_log.size < 2

        last = @cycle_log.last
        return true if last[:violations].zero?
        return true if last[:rate] < LOW_SUCCESS_RATE
        return true if @cycle_log.last(2).all? { |entry| entry[:delta] == 0 }
        return true if oscillating?

        false
      end

      def oscillating?
        signs = @cycle_log.last(3).map { |entry| entry[:delta] <=> 0 }
        return false if signs.size < 3
        signs.each_cons(2).all? { |x, y| x != 0 && x == -y }
      end

      def convergence_summary
        return "sweep: no cycles recorded" if @cycle_log.empty?
        count = @cycle_log.size
        last  = @cycle_log.last
        prev  = count > 1 ? @cycle_log[-2][:violations] : "?"
        osc   = oscillating? ? 1 : 0
        "sweep: iter=#{count} violations=#{prev}->#{last[:violations]} " \
          "fixed=#{last[:fixed]} deferred=#{last[:deferred]} rate=#{last[:rate]} oscillating=#{osc}"
      end

      # A→B→A within RENAME_WINDOW cycles signals oscillation (arxiv:2602.21833 §4.3).
      def rename_oscillation?(rel, old_src, new_src, cycle)
        old_names   = extract_names(old_src)
        new_names   = extract_names(new_src)
        removed_now = old_names - new_names
        added_now   = new_names - old_names
        history     = @rename_log[rel]
        oscillates  = history.last(RENAME_WINDOW).any? { |entry| names_reverted?(entry, added_now, removed_now) }
        history << { cycle:, removed: removed_now, added: added_now }
        @rename_log[rel] = history.last(RENAME_WINDOW * 2)
        oscillates
      end

      def names_reverted?(entry, added_now, removed_now)
        (entry[:removed] & added_now).any? && (entry[:added] & removed_now).any?
      end

      def extract_names(source) = source.scan(NAME_RE).flatten.compact.uniq

      def converged?(history)
        return false if history.size < 2
        prev, curr = history[-2], history[-1]
        return true if curr.zero?
        (prev - curr).abs.to_f / [prev, 1].max < @converge_threshold
      end

      def trajectory_stalled?(history)
        return false if history.size < 3
        deltas = history.each_cons(2).map { |a, b| a - b }
        weighted = deltas.last(@converge_window + 1).each_with_index.sum { |d, idx| d * (TRAJECTORY_GAMMA**idx) }
        weighted.abs < 1.0
      end

      def commit(msg)
        Master::AutoLoop::TARGETS.each { |d| Open3.capture2e("git", "-C", @root, "add", "--", d) }
        Open3.capture2e("git", "-C", @root, "commit", "-m", msg.to_s)
      end

      def git_dirty?
        out, = Open3.capture2e("git", "-C", @root, "status", "--porcelain")
        !out.strip.empty?
      end
    end
  end
end
