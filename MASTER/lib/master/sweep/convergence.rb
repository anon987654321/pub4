# frozen_string_literal: true

module Master
  class Sweep
    module Convergence
      private

      # A→B→A within RENAME_WINDOW cycles signals oscillation (arxiv:2602.21833 §4.3).
      def rename_oscillation?(rel, old_src, new_src, cycle)
        removed_now = extract_names(old_src) - extract_names(new_src)
        added_now   = extract_names(new_src) - extract_names(old_src)
        history     = @rename_log[rel]
        oscillates  = history.last(RENAME_WINDOW).any? { |e|
          (e[:removed] & added_now).any? && (e[:added] & removed_now).any?
        }
        history << { cycle:, removed: removed_now, added: added_now }
        @rename_log[rel] = history.last(RENAME_WINDOW * 2)
        oscillates
      end

      def extract_names(source) = source.scan(NAME_RE).flatten.compact.uniq

      def converged?(history)
        return false if history.size < 2
        prev, curr = history[-2], history[-1]
        return true if curr.zero?
        (prev - curr).abs.to_f / [prev, 1].max < CONVERGE_THRESHOLD
      end

      def trajectory_stalled?(history)
        return false if history.size < 3
        deltas = history.each_cons(2).map { |a, b| a - b }
        v = deltas.last(CONVERGE_WINDOW + 1).each_with_index.sum { |d, i| d * (TRAJECTORY_GAMMA**i) }
        v.abs < 1.0
      end

      def commit(msg)
        Open3.capture2e("git", "-C", @root, "add", "-A")
        Open3.capture2e("git", "-C", @root, "commit", "-m", msg.to_s)
      end

      def git_dirty?
        out, = Open3.capture2e("git", "-C", @root, "status", "--porcelain")
        !out.strip.empty?
      end
    end
  end
end
