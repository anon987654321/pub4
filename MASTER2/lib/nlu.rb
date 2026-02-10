# frozen_string_literal: true

module MASTER
  # Natural Language Understanding module
  # Converts natural language commands into structured intents
  # Standalone stub implementation for MASTER2
  class NLU
    INTENTS = %i[refactor analyze explain fix search show list help unknown].freeze

    INTENT_DESCRIPTIONS = {
      refactor: "Improve or refactor code in files",
      analyze: "Analyze code quality, patterns, or issues",
      explain: "Explain what code does or how it works",
      fix: "Fix bugs, errors, or issues in code",
      search: "Search for code, patterns, or files",
      show: "Display or show code, files, or information",
      list: "List files, directories, or items",
      help: "Get help or assistance",
      unknown: "Intent cannot be determined"
    }.freeze

    class << self
      # Classify intent from natural language input
      # @param text [String] Natural language command
      # @return [Hash] Intent classification result
      def classify_intent(text)
        return error_result("Empty input") if text.nil? || text.strip.empty?

        # Simple keyword-based classification
        normalized = text.downcase.strip

        intent = detect_intent(normalized)
        entities = extract_entities(text)

        {
          success: true,
          intent: intent,
          entities: entities,
          confidence: 0.8,
          text: text
        }
      rescue StandardError => e
        error_result("NLU error: #{e.message}")
      end

      private

      def detect_intent(normalized)
        case normalized
        when /refactor|improve|clean up|restructure/
          :refactor
        when /analyze|check|review|inspect/
          :analyze
        when /explain|what is|how does|tell me about/
          :explain
        when /fix|repair|correct|debug/
          :fix
        when /search|find|look for|locate/
          :search
        when /show|display|view|print/
          :show
        when /list|enumerate|show all/
          :list
        when /help|how to|assist/
          :help
        else
          :unknown
        end
      end

      def extract_entities(text)
        entities = {}

        # Extract file paths
        if text =~ /(\S+\.(rb|py|js|ts|go|rs|sh|zsh|bash))/
          entities[:file] = $1
        end

        # Extract directory paths
        if text =~ /in ([\w\/\-\.]+)/
          entities[:directory] = $1
        end

        entities
      end

      def error_result(message)
        {
          success: false,
          error: message,
          intent: :unknown,
          entities: {},
          confidence: 0.0
        }
      end
    end
  end
end
