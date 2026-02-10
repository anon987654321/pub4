# frozen_string_literal: true

module MASTER
  module NLU
    INTENTS = {
      refactor: /\b(refactor|clean|improve|simplify)\b/i,
      fix: /\b(fix|bug|error|broken|crash)\b/i,
      explain: /\b(explain|describe|what|how|why)\b/i,
      create: /\b(create|new|add|build|generate)\b/i,
      test: /\b(test|spec|verify|check)\b/i,
      search: /\b(search|find|grep|look)\b/i,
      deploy: /\b(deploy|ship|release|publish)\b/i,
    }.freeze

    def self.classify_intent(text)
      scores = INTENTS.map { |intent, pattern| [intent, text.scan(pattern).size] }
      best = scores.max_by(&:last)
      {
        intent: best.last > 0 ? best.first : :general,
        confidence: best.last > 0 ? [best.last * 0.3, 1.0].min : 0.0,
        text: text,
      }
    end
  end
end
