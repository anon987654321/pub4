# frozen_string_literal: true

module MASTER
  # Classifier — LLM-backed classification with regex fallback
  # Uses cheap-tier structured output for classification tasks
  # Falls back to regex heuristics when LLM is unavailable or budget exhausted
  module Classifier
    CLASSIFIERS_FILE = File.join(__dir__, "..", "data", "classifiers.yml")

    class << self
      def classify(classifier_name, input)
        config = classifiers[classifier_name.to_s]
        return nil unless config

        # Try LLM classification first (cheap tier, structured output)
        if defined?(LLM) && LLM.configured? && LLM.budget_remaining > 0.01
          result = llm_classify(config, input)
          return result if result
        end

        # Fall back to regex heuristics
        regex_classify(classifier_name, input) || config["default"]
      end

      def classifiers
        @classifiers ||= load_classifiers
      end

      def reload!
        @classifiers = nil
      end

      private

      def load_classifiers
        return {} unless File.exist?(CLASSIFIERS_FILE)
        config = YAML.safe_load_file(CLASSIFIERS_FILE) || {}
        config["classifiers"] || {}
      end

      def llm_classify(config, input)
        categories = config["categories"]
        prompt = <<~PROMPT
          Classify this input into exactly one category.

          Categories:
          #{categories.map { |k, v| "- #{k}: #{v}" }.join("\n")}

          Input: #{input[0..500]}

          Respond with ONLY the category name, nothing else.
        PROMPT

        result = LLM.ask(prompt, tier: :cheap)
        return nil unless result.ok?

        answer = result.value[:content].strip.downcase.to_s
        categories.key?(answer) ? answer : nil
      rescue StandardError
        nil
      end

      # Regex fallback heuristics (zero-cost)
      def regex_classify(classifier_name, input)
        case classifier_name.to_s
        when "pattern_selection"
          return "pre_act" if input.match?(/\b(then|after that|next|finally|step\s*\d|first.*then)\b/i)
          return "pre_act" if input.match?(/\b(build|create|implement|develop)\b.*\b(and|with)\b/i)
          return "rewoo" if input.match?(/\b(explain|describe|summarize|compare|analyze)\b/i) &&
                            !input.match?(/\b(file|code|execute|run)\b/i)
          return "reflexion" if input.match?(/\b(fix|debug|correct|improve|refactor)\b/i)
          return "reflexion" if input.match?(/\b(don't break|carefully|safely)\b/i)
          "react"
        when "query_complexity"
          if input.length < 200 &&
             !input.match?(/\b(file|read|write|analyze|fix|search|browse|run|execute|test|review)\b/i) &&
             !input.match?(/\b(create|update|modify|delete|install|build)\b/i)
            "simple"
          else
            "complex"
          end
        end
      end
    end
  end
end
