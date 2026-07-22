# frozen_string_literal: true

module Master
  module Review
    # Hybrid-Norm verdict (RLVR): combine deterministic verifiable signals (parse / lint /
    # tests / scanner) with an LLM rubric score. Any hard signal failing is an automatic block;
    # otherwise the rubric decides. Refs: rubric + verifiable rewards (arXiv:2602.05125).
    class Verdict
      Result = Struct.new(:pass, :score, :reasons, keyword_init: true) do
        def pass? = pass
      end

      def initialize(rubric_threshold: 0.6)
        @threshold = rubric_threshold
      end

      # deterministic: Hash of name => Boolean (false means a hard, non-negotiable failure).
      # rubric_score: 0.0..1.0 from the council/judge.
      def call(deterministic:, rubric_score:)
        hard_failures = (deterministic || {}).reject { |_name, ok| ok }.keys
        return result(false, 0.0, hard_failures.map { |name| "failed #{name}" }) unless hard_failures.empty?

        score = rubric_score.to_f.clamp(0.0, 1.0)
        pass = score >= @threshold
        result(pass, score, [pass ? "verified" : "rubric #{score} < #{@threshold}"])
      end

      private

      def result(pass, score, reasons)
        Result.new(pass:, score:, reasons:)
      end
    end
  end
end
