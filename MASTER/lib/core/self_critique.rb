# frozen_string_literal: true

module MASTER
  module Core
    class SelfCritique
      CONFIDENCE_THRESHOLD = 0.6
      MAX_RETRIES = 3

      def self.critique_response(task:, response:, model: 'cheap')
        prompt = <<~PROMPT
          You are evaluating your own work. Be brutally honest.
          
          Task: #{task}
          
          Your response: #{response}
          
          Rate this response on:
          1. Correctness (0-1): Does it solve the task?
          2. Completeness (0-1): Does it address all aspects?
          3. Clarity (0-1): Is it clear and well-structured?
          
          Return ONLY valid JSON:
          {
            "correctness": 0.0-1.0,
            "completeness": 0.0-1.0,
            "clarity": 0.0-1.0,
            "overall_confidence": 0.0-1.0,
            "issues": ["issue1", "issue2"],
            "suggestions": ["suggestion1", "suggestion2"]
          }
        PROMPT

        critique_text = MASTER::LLM.call(
          prompt,
          model: model,
          temperature: 0.3,
          max_tokens: 400
        )

        parse_critique(critique_text)
      end

      def self.should_retry?(critique)
        return false unless critique
        critique[:overall_confidence] < CONFIDENCE_THRESHOLD
      end

      def self.extract_strength(critique)
        return 0.5 unless critique
        
        weights = { correctness: 0.4, completeness: 0.3, clarity: 0.3 }
        
        weighted_sum = weights.sum do |key, weight|
          (critique[key] || 0.5) * weight
        end
        
        weighted_sum.clamp(0.0, 1.0)
      end

      private

      def self.parse_critique(text)
        json_match = text.match(/\{[^{}]*\}/m)
        return default_critique unless json_match

        parsed = JSON.parse(json_match[0], symbolize_names: true)
        
        {
          correctness: parsed[:correctness]&.to_f || 0.5,
          completeness: parsed[:completeness]&.to_f || 0.5,
          clarity: parsed[:clarity]&.to_f || 0.5,
          overall_confidence: parsed[:overall_confidence]&.to_f || 0.5,
          issues: Array(parsed[:issues]),
          suggestions: Array(parsed[:suggestions])
        }
      rescue JSON::ParserError
        default_critique
      end

      def self.default_critique
        {
          correctness: 0.5,
          completeness: 0.5,
          clarity: 0.5,
          overall_confidence: 0.5,
          issues: ["Unable to parse self-critique"],
          suggestions: []
        }
      end
    end
  end
end
