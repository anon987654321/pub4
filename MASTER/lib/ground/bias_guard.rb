# frozen_string_literal: true

module Master
  module Ground
    class BiasGuard
      BIAS_PATH = "data/biases.yml".freeze
      SEVERITY_WEIGHT = { critical: 4.0, error: 3.0, warning: 2.0, info: 1.0 }.freeze

      def initialize(root: Master::ROOT)
        @root = root
        @biases = load_biases
      end

      def annotate(proposal)
        hits = detect(proposal)
        return proposal if hits.empty?

        note = hits.map { |name| "#{name}: #{countermeasure(name)}" }.join("; ")
        proposal.to_h.merge(
          reason: "#{proposal.reason} | bias check: #{note}",
          confidence: [proposal.confidence.to_f - 0.1, 0.1].max,
        )
      end

      def detect(proposal)
        text = "#{proposal.action} #{proposal.reason}".downcase
        hits = []
        hits << "confirmation_bias" if text.match?(/\b(fix|violation|same fix|still carries|scanner result)\b/) && !text.match?(/\b(alternative|tradeoff|counter|review|why)\b/)
        hits << "sunk_cost_bias" if text.match?(/\b(continue|more|again|retry)\b/) && !text.match?(/\brollback|simpler|stop\b/)
        hits << "authority_bias" if text.match?(/\b(llm|model|scanner|rubocop|reek)\b/) && !text.match?(/\bevidence|local|test|scan:/)
        hits << "sycophancy" if text.match?(/\b(great idea|absolutely|of course|as you wish)\b/) && !text.match?(/\brisk|tradeoff|however|but\b/)
        hits << "simulation_bias" if text.match?(/\b(will fix|would work|should pass|going to|plan to)\b/) && !text.match?(/\bdiff|passed|exit|sha256|applied\b/)
        hits << "anchoring_bias" if text.match?(/\b(first approach|initial fix|as before)\b/) && !text.match?(/\balternative|option b|second pass\b/)
        hits << "availability_bias" if text.match?(/\b(new (file|class|module|pattern))\b/) && !text.match?(/\bexisting|reuse|search|found\b/)
        hits << "premature_optimization" if text.match?(/\b(cache|optimize|perf|benchmark)\b/) && !text.match?(/\bmeasured|profile|hot path|n\+\s*1\b/)
        hits << "aesthetic_neglect" if text.match?(/\b(view|scss|css|ui|erb|face)\b/) && !text.match?(/\baesthetic|spacing|contrast|touch|flat|token\b/)
        hits << "recency_bias" if text.match?(/\b(latest|just added|newest)\b/) && !text.match?(/\bseverity|age|frequency\b/)
        hits.uniq
      end

      def priority_score(severity:, frequency:, age_days:)
        sev = SEVERITY_WEIGHT.fetch(severity.to_sym, 1.0)
        age = [[age_days.to_f, 0.0].max, 365.0].min
        sev * frequency.to_f * (1.0 + (age / 30.0))
      end

      private

      def countermeasure(name)
        @biases.dig(name, "countermeasure").to_s
      end

      def load_biases
        path = File.join(@root, BIAS_PATH)
        File.exist?(path) ? Master.load_yaml(path) : {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "BiasGuard.load_biases")
        {}
      end
    end
  end
end
