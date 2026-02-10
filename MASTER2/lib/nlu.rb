# frozen_string_literal: true

module MASTER
  # NLU - Natural Language Understanding stub
  # Simplified version for MASTER2 autonomy
  module NLU
    extend self
    
    def understand(text)
      {
        text: text,
        intent: detect_intent(text),
        entities: extract_entities(text)
      }
    end
    
    def detect_intent(text)
      return :refactor if text.match?(/refactor|improve|optimize|clean/i)
      return :fix if text.match?(/fix|repair|debug|solve/i)
      return :create if text.match?(/create|add|new|build/i)
      return :analyze if text.match?(/analyze|check|review|inspect/i)
      return :question if text.match?(/\?|what|how|why|when|where/i)
      :unknown
    end
    
    def extract_entities(text)
      entities = []
      
      # Extract file paths
      text.scan(%r{[\w/]+\.[\w]+}) do |match|
        entities << { type: :file, value: match }
      end
      
      # Extract code symbols
      text.scan(/\b[A-Z]\w*::\w+/) do |match|
        entities << { type: :class, value: match }
      end
      
      entities
    end
  end
end
