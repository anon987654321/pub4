# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      class PassRunner
        # Detects a pass making no real progress — exact repeat (oscillation),
        # the same violation recurring across N passes (cycle), or the
        # violation count holding flat across a window (plateau) — and
        # triggers rollback. Separate concern from running a pass.
        module StagnationDetection
          private

          def stagnant?(history, seen_snapshots, recurring_violations, found, pass)
            return true if oscillating?(seen_snapshots, found, pass)
            return true if recurrence_cycle?(recurring_violations, found, pass)

            history << found.size
            plateaued?(history, found, pass)
          end

          def oscillating?(seen_snapshots, found, pass)
            snap = violation_snapshot(found)
            if seen_snapshots.include?(snap)
              @bus&.publish("fix_loop:oscillation", pass:, violations: found.size)
              @homeostat&.observe(:llm_failure)
              trigger_rollback("fix loop oscillation")
              return true
            end
            seen_snapshots << snap
            false
          end

          def recurrence_cycle?(recurring_violations, found, pass)
            recurring = recurring_violation(found, recurring_violations)
            return false unless recurring

            @bus&.publish("fix_loop:cycle_detected", pass:, threshold: @plateau_window, violation: recurring)
            @homeostat&.observe(:llm_failure)
            trigger_rollback("fix loop cycle detected")
            true
          end

          def plateaued?(history, found, pass)
            window = @plateau_window
            return false unless history.size >= window && history.last(window).uniq.size == 1

            @bus&.publish("fix_loop:plateau", pass:, violations: found.size)
            @homeostat&.observe(:llm_failure)
            true
          end

          def recurring_violation(found, recurring_violations)
            current = found.to_h { |v| [violation_key(v), v] }
            (recurring_violations.keys - current.keys).each { |key| recurring_violations.delete(key) }
            current.each do |key, violation|
              recurring_violations[key] += 1
              return violation if recurring_violations[key] >= @plateau_window
            end
            nil
          end

          def violation_snapshot(found)
            Digest::SHA256.hexdigest(found.map { |v| violation_key(v) }.sort.join("|"))
          end

          def violation_key(v) = "#{v[:rule]}:#{v[:file]}:#{v[:line]}"

          def trigger_rollback(message)
            return unless @rollback
            @rollback.call(Master::Result.err(message, category: :policy))
          rescue StandardError => e
            @bus&.publish("fix_loop:rollback_error", error: e.message)
          end
        end
      end
    end
  end
end
