# frozen_string_literal: true

require "json"

module MASTER
  module Stages
    # Pressure Tank: Compresses and refines user input through 8-phase discovery
    class Compress
      include Dry::Monads[:result]

      MAX_INPUT_SIZE = 50_000 # characters

      def call(input)
        # Phase 1: Parse raw text
        text = parse(input)
        return Failure("No input text provided") if text.empty?
        return Failure("Input too large: #{text.length} chars (max #{MAX_INPUT_SIZE})") if text.length > MAX_INPUT_SIZE

        # Phase 2: Identify intent
        intent = classify(text)

        # Phase 3: Extract entities
        entities = extract(text)

        # Phase 4: Load relevant axioms from DB (TODO: implement filtering logic)
        axioms = DB.axioms(protection: "PROTECTED") || []

        # Phase 5: Load relevant council members (TODO: implement task-based filtering)
        council = DB.council || []

        # Phase 6: Apply Strunk & White compression (TODO: implement omit needless words)
        compressed_text = compress(text)

        # Phase 7: Build structured context hash
        enriched = {
          original_text: text,
          text: compressed_text,
          intent: intent,
          entities: entities,
          axioms: axioms,
          council: council
        }

        # Load zsh patterns for command/admin intents or when services are detected
        if intent == :command || intent == :admin || entities[:services]
          enriched[:zsh_patterns] = DB.zsh_patterns || []
          enriched[:openbsd_patterns] = DB.openbsd_patterns || []
        end

        # Phase 8: Return enriched input
        Success(input.is_a?(Hash) ? input.merge(enriched) : enriched)
      end

      private

      def parse(input)
        case input
        when String then input
        when Hash then input.fetch(:text) { input.fetch("text", "") }
        else ""
        end
      end

      def classify(text)
        # Fast path: regex pre-filter for obvious cases
        return :command if text.match?(/^(create|delete|update|run|execute)\b/i)
        
        # LLM path: use cheap model for structured classification
        model = LLM.pick
        return regex_fallback_classify(text) unless model
        
        prompt = <<~PROMPT
          Classify this input. Return ONLY one word: question, refactor, admin, command, or general.
          Input: #{text}
        PROMPT
        
        response = LLM.chat(model: model).ask(prompt)
        result = response.content.strip.downcase.to_sym
        
        # Track cost
        if response.respond_to?(:tokens_in) && response.respond_to?(:tokens_out)
          LLM.log_cost(
            model: model,
            tokens_in: response.tokens_in || 0,
            tokens_out: response.tokens_out || 0
          )
        end
        
        result
      rescue
        regex_fallback_classify(text)
      end
      
      def regex_fallback_classify(text)
        # Simple keyword-based intent detection
        return :question if text.match?(/\?$|\bwhat\b|\bhow\b|\bwhy\b|\bwhen\b/i)
        return :refactor if text.match?(/\brefactor\b|\bimprove\b|\boptimize\b/i)
        return :admin if text.match?(/\bpf\b|\bhttpd\b|\brelayd\b|\bconfig\b/i)
        return :command if text.match?(/^(create|delete|update|run|execute)\b/i)
        :general
      end

      def extract(text)
        model = LLM.pick
        return regex_fallback_extract(text) unless model
        
        prompt = <<~PROMPT
          Extract entities from this text. Return JSON:
          {"files": [...], "services": [...], "configs": [...]}
          Only include entities actually mentioned. Empty arrays for missing types.
          Text: #{text}
        PROMPT
        
        response = LLM.chat(model: model).ask(prompt)
        result = JSON.parse(response.content, symbolize_names: true)
        
        # Track cost
        if response.respond_to?(:tokens_in) && response.respond_to?(:tokens_out)
          LLM.log_cost(
            model: model,
            tokens_in: response.tokens_in || 0,
            tokens_out: response.tokens_out || 0
          )
        end
        
        result
      rescue
        regex_fallback_extract(text)
      end
      
      def regex_fallback_extract(text)
        entities = {}

        # Extract file paths
        files = text.scan(%r{(?:^|\s)([\w./\-]+\.(?:rb|js|py|txt|yml|yaml|json|md))(?:\s|$)}).flatten
        entities[:files] = files unless files.empty?

        # Extract service names
        services = text.scan(/\b(httpd|relayd|pf|nginx|postgresql|redis|acme-client|bgpd|ospfd|rad|dhcpd|ntpd|sshd|smtpd|cron)\b/i).flatten.map(&:downcase).uniq
        entities[:services] = services unless services.empty?

        entities
      end

      def compress(text)
        # Basic Strunk & White: remove filler words
        compressed = text.dup
        
        # Load patterns from DB, with fallback to hardcoded
        begin
          filler_words = DB.compression_patterns(category: "filler").map { |p| p["pattern"] }
          phrases = DB.compression_patterns(category: "phrase").map { |p| p["pattern"] }
          
          unless filler_words.empty?
            filler_pattern = /\b(#{filler_words.join("|")})\b/i
            compressed = compressed.gsub(filler_pattern, "")
          end
          
          phrases.each do |phrase|
            compressed = compressed.gsub(/#{Regexp.escape(phrase)}/i, "")
          end
        rescue
          # Fallback to hardcoded patterns
          fillers = [
            /\b(just|really|very|quite|rather|somewhat|basically|actually|literally)\b/i,
            /\b(in order to|due to the fact that|at this point in time)\b/i
          ]
          fillers.each { |pattern| compressed = compressed.gsub(pattern, "") }
        end

        # Clean up extra whitespace
        compressed = compressed.gsub(/\s+/, " ").strip

        compressed
      end
    end
  end
end
