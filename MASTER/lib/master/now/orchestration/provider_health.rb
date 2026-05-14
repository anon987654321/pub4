# frozen_string_literal: true

module Master
  module Now
  module Orchestration
    class ProviderHealth
      DEFAULT_SCORE = 1.0
      PENALTY_STEP  = 0.1
      MIN_SCORE     = 0.0

      def initialize
        @providers = Hash.new { |h, k| h[k] = default_state }
      end

      def record_success(provider)
        state = @providers[provider.to_s]
        state[:successes] += 1
        state[:score] = [state[:score] + PENALTY_STEP, DEFAULT_SCORE].min
        state
      end

      def record_failure(provider)
        state = @providers[provider.to_s]
        state[:failures] += 1
        state[:score] = [state[:score] - PENALTY_STEP, MIN_SCORE].max
        state[:quarantined] = true if state[:score] <= 0.2
        state
      end

      def healthy?(provider)
        !@providers[provider.to_s][:quarantined]
      end

      def score(provider)
        @providers[provider.to_s][:score]
      end

      def snapshot
        @providers.transform_values(&:dup)
      end

      private

      def default_state
        {
          successes: 0,
          failures: 0,
          quarantined: false,
          score: DEFAULT_SCORE
        }
      end
    end
  end
  end
end
