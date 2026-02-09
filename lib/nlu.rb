# frozen_string_literal: true

module MASTER
  # Natural Language Understanding module
  # Converts natural language commands into structured intents using LLM
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
      # Parse natural language input into structured intent
      # @param input [String] Natural language command
      # @param context [Hash] Optional conversation context
      # @return [Hash] Structured intent with entities and confidence
      def parse(input, context: {})
        return error_result("Empty input") if input.nil? || input.strip.empty?

        # Build prompt for intent classification
        prompt = build_classification_prompt(input, context)

        # Call LLM for classification
        result = call_llm(prompt)

        if result[:success]
          parse_llm_response(result[:response], input)
        else
          # Fallback to pattern matching if LLM fails
          fallback_parse(input)
        end
      rescue StandardError => e
        error_result("NLU error: #{e.message}")
      end

      # Parse with explicit JSON schema for structured output
      # @param input [String] Natural language command
      # @param context [Hash] Optional conversation context
      # @return [Hash] Structured intent with entities and confidence
      def parse_structured(input, context: {})
        return error_result("Empty input") if input.nil? || input.strip.empty?

        prompt = build_classification_prompt(input, context)
        schema = intent_schema

        # Try to use LLM with JSON schema if available
        if defined?(MASTER::LLM) && MASTER::LLM.respond_to?(:ask_json)
          result = MASTER::LLM.ask_json(prompt, schema: schema, tier: :fast)
          
          if result.ok?
            data = result.value[:content]
            return normalize_intent(data) if data.is_a?(Hash)
          end
        end

        # Fallback to regular parse
        parse(input, context: context)
      rescue StandardError => e
        error_result("NLU structured error: #{e.message}")
      end

      # Extract file/directory entities from text
      # @param text [String] Text to extract from
      # @return [Array<String>] List of potential file/directory paths
      def extract_files(text)
        files = []

        # Match file extensions
        files.concat(text.scan(/\b[\w\/\-\.]+\.(?:rb|js|py|sh|zsh|bash|yml|yaml|json)\b/))

        # Match directory patterns
        files.concat(text.scan(/\b[\w\-]+\/[\w\/\-\.]*\b/))

        # Match quoted paths
        files.concat(text.scan(/["']([^"']+\.[\w]+)["']/).flatten)

        files.uniq
      end

      # Extract intent keywords from text
      # @param text [String] Text to analyze
      # @return [Array<Symbol>] Potential intents based on keywords
      def extract_intent_keywords(text)
        intents = []
        normalized = text.downcase

        # Refactor keywords
        intents << :refactor if normalized.match?(/\b(refactor|improve|optimize|clean|rewrite)\b/)

        # Analyze keywords
        intents << :analyze if normalized.match?(/\b(analyze|check|inspect|review|audit)\b/)

        # Explain keywords
        intents << :explain if normalized.match?(/\b(explain|describe|what|how|why)\b/)

        # Fix keywords
        intents << :fix if normalized.match?(/\b(fix|repair|correct|debug|solve)\b/)

        # Search keywords
        intents << :search if normalized.match?(/\b(search|find|locate|look for)\b/)

        # Show keywords
        intents << :show if normalized.match?(/\b(show|display|print|output)\b/)

        # List keywords
        intents << :list if normalized.match?(/\b(list|enumerate|show all)\b/)

        intents.uniq
      end

      private

      # Build prompt for LLM classification
      # @param input [String] User input
      # @param context [Hash] Conversation context
      # @return [String] Formatted prompt
      def build_classification_prompt(input, context)
        prompt = <<~PROMPT
          You are analyzing a command for a code refactoring system. 
          Classify the intent and extract relevant entities.

          Available intents:
          #{INTENT_DESCRIPTIONS.map { |k, v| "- #{k}: #{v}" }.join("\n")}

          User command: "#{input}"
        PROMPT

        if context[:previous_command]
          prompt += "\nPrevious command: #{context[:previous_command]}"
        end

        if context[:current_file]
          prompt += "\nCurrent context: #{context[:current_file]}"
        end

        prompt += <<~PROMPT

          Respond with JSON containing:
          {
            "intent": "one of: #{INTENTS.join(', ')}",
            "entities": {
              "files": ["list of file paths mentioned"],
              "directories": ["list of directory paths mentioned"],
              "patterns": ["list of code patterns or search terms"],
              "target": "main target of the command"
            },
            "confidence": 0.0-1.0,
            "clarification_needed": false or true,
            "suggested_question": "optional clarifying question if needed"
          }

          Only respond with valid JSON, no other text.
        PROMPT

        prompt
      end

      # Call LLM for classification
      # @param prompt [String] Classification prompt
      # @return [Hash] Result with success status and response
      def call_llm(prompt)
        # Check if LLM is available
        return { success: false, error: "LLM not available" } unless defined?(MASTER::LLM)

        result = MASTER::LLM.ask(prompt, tier: :fast)

        if result.ok?
          { success: true, response: result.value[:content] }
        else
          { success: false, error: result.error }
        end
      rescue StandardError => e
        { success: false, error: e.message }
      end

      # Parse LLM JSON response
      # @param response [String] LLM response text
      # @param input [String] Original input
      # @return [Hash] Structured intent
      def parse_llm_response(response, input)
        # Extract JSON from response (handle markdown code blocks)
        json_text = response.strip
        json_text = json_text[/```(?:json)?\n(.*?)\n```/m, 1] || json_text
        json_text = json_text.strip

        data = JSON.parse(json_text, symbolize_names: true)
        normalize_intent(data)
      rescue JSON::ParserError => e
        # If JSON parsing fails, try to extract intent from text
        intent = extract_intent_from_text(response)
        {
          intent: intent,
          entities: { files: extract_files(input) },
          confidence: 0.5,
          method: :text_extraction,
          error: "JSON parse failed: #{e.message}"
        }
      end

      # Normalize intent data structure
      # @param data [Hash] Raw intent data
      # @return [Hash] Normalized intent structure
      def normalize_intent(data)
        intent_sym = data[:intent].to_sym
        intent_sym = :unknown unless INTENTS.include?(intent_sym)

        {
          intent: intent_sym,
          entities: data[:entities] || {},
          confidence: data[:confidence] || 0.7,
          clarification_needed: data[:clarification_needed] || false,
          suggested_question: data[:suggested_question],
          method: :llm
        }
      end

      # Fallback pattern-based parsing
      # @param input [String] User input
      # @return [Hash] Basic intent structure
      def fallback_parse(input)
        keywords = extract_intent_keywords(input)
        intent = keywords.first || :unknown
        files = extract_files(input)

        {
          intent: intent,
          entities: {
            files: files,
            target: input.strip
          },
          confidence: keywords.any? ? 0.6 : 0.3,
          clarification_needed: keywords.empty?,
          method: :fallback
        }
      end

      # Extract intent from text response
      # @param text [String] Response text
      # @return [Symbol] Extracted intent
      def extract_intent_from_text(text)
        normalized = text.downcase
        
        INTENTS.each do |intent|
          return intent if normalized.include?(intent.to_s)
        end

        # Try keywords
        keywords = extract_intent_keywords(text)
        keywords.first || :unknown
      end

      # Define JSON schema for structured output
      # @return [Hash] JSON schema
      def intent_schema
        {
          type: "object",
          properties: {
            intent: {
              type: "string",
              enum: INTENTS.map(&:to_s)
            },
            entities: {
              type: "object",
              properties: {
                files: { type: "array", items: { type: "string" } },
                directories: { type: "array", items: { type: "string" } },
                patterns: { type: "array", items: { type: "string" } },
                target: { type: "string" }
              }
            },
            confidence: {
              type: "number",
              minimum: 0,
              maximum: 1
            },
            clarification_needed: { type: "boolean" },
            suggested_question: { type: "string" }
          },
          required: ["intent", "entities", "confidence"]
        }
      end

      # Create error result
      # @param message [String] Error message
      # @return [Hash] Error structure
      def error_result(message)
        {
          intent: :unknown,
          entities: {},
          confidence: 0.0,
          error: message,
          method: :error
        }
      end
    end
  end
end
