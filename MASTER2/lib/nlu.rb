# frozen_string_literal: true

module MASTER
  # Natural Language Understanding module
  # Converts natural language commands into structured intents using LLM
  class NLU
    INTENTS = %i[refactor analyze explain fix search show list help unknown].freeze

    # Signal types detected by classify_signals — replaces scattered regexes
    SIGNAL_TYPES = %i[
      context_shift memory_trigger complex_task simple_command
      self_run_request lint_request health_request status_request
      shell_paste diff_paste security_concern identity_query
    ].freeze

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
        llm_result = call_llm(prompt)

        if llm_result[:success]
          parse_llm_response(llm_result[:response], input)
        else
          # Fallback to pattern matching if LLM fails
          fallback_parse(input)
        end
      rescue StandardError => err
        error_result("NLU error: #{err.message}")
      end

      # Classify all semantic signals in one LLM call.
      # Replaces scattered detection regexes across intake, pipeline, commands.
      # Returns a Set of matched SIGNAL_TYPES symbols.
      def classify_signals(text)
        return Set.new if text.nil? || text.strip.empty?

        prompt = <<~PROMPT
          Classify which signals are present in this user input. Return ONLY a JSON array of matching signal names.

          Signals:
          - context_shift: user is changing topic ("now", "next", "moving on", "new task", "ok so", "let's")
          - memory_trigger: references prior conversation ("you suggested", "last time", "as before", "continue")
          - complex_task: requests building/creating/deploying a system, app, or service
          - simple_command: a short directive command (scan, fix, lint, help, version, exit, show, list)
          - self_run_request: wants to refactor/rewrite the entire codebase or all files
          - lint_request: wants to lint, validate, or syntax-check files across a project
          - health_request: asking about system health, diagnostics, or setup
          - status_request: asking about current status, summary, or progress
          - shell_paste: pasted terminal output (user@host$, "Last login:", command output)
          - diff_paste: pasted a code diff (diff --git, +++, ---, @@)
          - security_concern: mentions security, auth, injection, credentials, or unsafe patterns
          - identity_query: asking "who are you" or "what are you"

          Input: "#{text.gsub('"', '\"').slice(0, 500)}"

          Respond with ONLY a JSON array, e.g. ["context_shift","simple_command"]
        PROMPT

        if defined?(MASTER::LLM) && MASTER::LLM.configured?
          result = MASTER::LLM.ask(prompt, tier: :fast)
          if result.respond_to?(:ok?) && result.ok?
            raw = result.value[:content].to_s.strip
            raw = raw[/\[.*\]/m] || "[]"
            signals = JSON.parse(raw).map(&:to_sym) & SIGNAL_TYPES
            return Set.new(signals)
          end
        end

        fallback_classify_signals(text)
      rescue StandardError
        fallback_classify_signals(text)
      end

      # Deterministic fallback when LLM unavailable — keeps old regex behavior
      def fallback_classify_signals(text)
        signals = Set.new
        t = text.to_s
        low = t.downcase

        signals << :shell_paste   if t.match?(/^\w+@[\w.-]+.*\$\s+/) || low.include?("last login:")
        signals << :diff_paste    if t.match?(/^\s*diff --git\b/) || t.match?(/^\s*@@\s+/)
        signals << :context_shift if low.match?(/\b(now|next|moving on|new task|start fresh|forget|done with)\b/) ||
                                     low.match?(/^(ok|okay|right|fine|good|cool|thanks)[,.]?\s+(now|so|let'?s|can you)/)
        signals << :memory_trigger if low.match?(/\b(you suggested|we decided|last time|as before|continue|the plan)\b/)
        signals << :complex_task   if low.match?(/\b(build|create|implement|deploy|architect|refactor)\b.*\b(system|app|service|pipeline|server|api)\b/)
        signals << :simple_command if low.match?(/\A\s*(scan|fix|lint|check|test|help|version|clear|exit|quit|show|list)\b/)
        signals << :self_run_request if low.match?(/\b(self.?run|entire repo|all files|codebase|every file)\b/)
        signals << :lint_request     if low.match?(/\b(lint|validate|syntax.check)\b.*\b(all|repo|files)\b/)
        signals << :health_request   if low.match?(/\b(health|diagnostic|doctor|check setup)\b/)
        signals << :status_request   if low.match?(/\b(status|where are we|summary)\b/)
        signals << :security_concern if low.match?(/\b(security|auth|injection|unsafe|credential)\b/)
        signals << :identity_query   if low.match?(/\bwho are you\b|\bwhat are you\b|\byour name\b/)

        signals
      end
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
            response_data = result.value[:content]
            return normalize_intent(response_data) if response_data.is_a?(Hash)
          end
        end

        # Fallback to regular parse
        parse(input, context: context)
      rescue StandardError => err
        error_result("NLU structured error: #{err.message}")
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

        # Help keywords
        intents << :help if normalized.match?(/\b(help|assist|guide)\b/)

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
      rescue StandardError => err
        { success: false, error: err.message }
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
      rescue JSON::ParserError => err
        # If JSON parsing fails, try to extract intent from text
        intent = extract_intent_from_text(response)
        {
          intent: intent,
          entities: { files: extract_files(input) },
          confidence: 0.5,
          method: :text_extraction,
          error: "JSON parse failed: #{err.message}"
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
