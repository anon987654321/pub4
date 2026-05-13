# frozen_string_literal: true

module Master
  module Runtime
    class Experience
      DECAY = 0.99

      def initialize
        @scores = {}
      end

      def record(plan:, score:)
        signature = signature_for(plan)
        current = (@scores[signature] ||= {
          "count" => 0.0,
          "score" => 0.0
        })

        current["count"] = (current["count"] * DECAY) + 1.0
        current["score"] = ((current["score"] * DECAY) + score.to_f) / 2.0

        current
      end

      def score(plan)
        signature = signature_for(plan)
        entry = @scores[signature]
        return rand * 0.05 unless entry

        entry["score"]
      end

      def signature_for(plan)
        Array(plan).map do |step|
          step[:tool] || step["tool"] || :unknown
        end.join("->")
      end
    end
  end
end
