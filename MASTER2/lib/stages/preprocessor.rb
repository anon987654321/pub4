# frozen_string_literal: true

module MASTER
  module Stages
    class Preprocessor
      def call(input)
        text = extract_text(input)
        return Result.err("No input text provided") if text.empty?

        intent = classify_intent(text)
        entities = extract_entities(text)
        axioms = DB.axioms(protection: "PROTECTED") || []
        council = DB.council_members || []
        compressed_text = compress_text(text)

        enriched = {
          original_text: text,
          text: compressed_text,
          intent: intent,
          entities: entities,
          axioms: axioms,
          council: council
        }

        if intent == :command || intent == :admin || entities[:services]
          enriched[:zsh_patterns] = DB.zsh_patterns || []
        end

        Result.ok(input.is_a?(Hash) ? input.merge(enriched) : enriched)
      end

      private

      def extract_text(input)
        case input
        when String then input
        when Hash then input[:text] || input["text"] || ""
        else ""
        end
      end

      def classify_intent(text)
        return :question if text.match?(/\?$|\bwhat\b|\bhow\b|\bwhy\b|\bwhen\b/i)
        return :refactor if text.match?(/\brefactor\b|\bimprove\b|\boptimize\b/i)
        return :admin if text.match?(/\bpf\b|\bhttpd\b|\brelayd\b|\bconfig\b/i)
        return :command if text.match?(/^(create|delete|update|run|execute)\b/i)
        :general
      end

      def extract_entities(text)
        entities = {}

        files = text.scan(%r{(?:^|\s)([\w./\-]+\.(?:rb|js|py|txt|yml|yaml|json|md))(?:\s|$)}).flatten
        entities[:files] = files unless files.empty?

        services = text.scan(/\b(httpd|relayd|pf|nginx|postgresql|redis)\b/i).flatten.map(&:downcase).uniq
        entities[:services] = services unless services.empty?

        entities
      end

      def compress_text(text)
        compressed = text.dup
        
        fillers = [
          /\b(just|really|very|quite|rather|somewhat|basically|actually|literally)\b/i,
          /\b(in order to|due to the fact that|at this point in time)\b/i
        ]
        
        fillers.each { |pattern| compressed.gsub!(pattern, "") }
        compressed = compressed.gsub(/\s+/, " ").strip
        
        compressed
      end
    end
  end
end
