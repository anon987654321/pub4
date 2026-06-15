# frozen_string_literal: true

module Master
  module Judge
    module Council
      # CV04/CV05: vote aggregation with confidence score.
      class Vote
        def initialize(soul_path: Master.data_path("soul.yml"))
          @soul_path = soul_path
        end

        def tally(votes)
          return { winner: nil, confidence: 0.0, tie: true } if votes.empty?

          grouped = votes.group_by { |v| v[:position] || infer_position(v) }
          winner_key, winner_votes = grouped.max_by { |_, vs| vs.size }
          tie = grouped.values.count { |vs| vs.size == winner_votes.size } > 1
          tie_breaker = tie ? soul_golden_rule : winner_key
          confidence = (winner_votes.sum { |v| v[:confidence] || 0.5 } / winner_votes.size.to_f).round(2)
          { winner: tie_breaker, confidence:, tie:, votes: winner_votes.size }
        end

        private

        def infer_position(vote)
          vote[:feedback].to_s.strip.start_with?(/VETO|against|reject/i) ? :reject : :accept
        end

        def soul_golden_rule
          soul = Master.load_yaml(@soul_path) || {}
          soul.dig("absolute", "golden_rule") || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        end
      end
    end
  end
end