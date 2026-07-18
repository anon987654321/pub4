# frozen_string_literal: true

module Master
  module Fix
    class Homeostat
      # Cognitive health predicates derived from error pressure, fatigue, and
      # energy — separate from Homeostat's own state-decay/event-observation core.
      module HealthPredicates
        def healthy? = !degraded? && !critical?

        def critical?
          t = HEALTH_THRESHOLDS[:critical]
          @state[:error_rate] >= t[:error_rate] ||
            @state[:fatigue] >= t[:fatigue] ||
            @state[:energy] <= t[:energy]
        end

        def degraded?
          return false if critical?
          t = HEALTH_THRESHOLDS[:degraded]
          @state[:error_rate] >= t[:error_rate] ||
            @state[:fatigue] >= t[:fatigue] ||
            @state[:energy] <= t[:energy]
        end

        def health_status
          return :critical if critical?
          return :degraded if degraded?
          :healthy
        end
      end
    end
  end
end
