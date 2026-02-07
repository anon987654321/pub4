# frozen_string_literal: true

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
        # Simple keyword-based intent detection
        return :question if text.match?(/\?$|\bwhat\b|\bhow\b|\bwhy\b|\bwhen\b/i)
        return :refactor if text.match?(/\brefactor\b|\bimprove\b|\boptimize\b/i)
        return :admin if text.match?(/\bpf\b|\bhttpd\b|\brelayd\b|\bconfig\b/i)
        return :command if text.match?(/^(create|delete|update|run|execute)\b/i)
        :general
      end

      def extract(text)
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
        
        # Remove common filler phrases
        fillers = [
          /\b(just|really|very|quite|rather|somewhat|basically|actually|literally)\b/i,
          /\b(in order to|due to the fact that|at this point in time)\b/i
        ]

        fillers.each { |pattern| compressed = compressed.gsub(pattern, "") }

        # Clean up extra whitespace
        compressed = compressed.gsub(/\s+/, " ").strip

        compressed
      end
    end
  end
end
