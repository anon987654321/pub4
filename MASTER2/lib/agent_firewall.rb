# frozen_string_literal: true

module MASTER
  class AgentFirewall
    Rule = Struct.new(:action, :direction, :pattern, :quick, :tag, keyword_init: true)

    DEFAULT_RULES = [
      # Block prompt injections in both directions
      Rule.new(action: :block, pattern: /ignore (?:all )?(?:previous|above|prior) instructions/i, quick: true),
      Rule.new(action: :block, pattern: /you are now/i, quick: true),
      Rule.new(action: :block, pattern: /new system prompt/i, quick: true),
      Rule.new(action: :block, pattern: /forget (?:everything|all|your)/i, quick: true),
      Rule.new(action: :block, pattern: /override (?:axiom|principle|rule)/i, quick: true),
      Rule.new(action: :block, pattern: /disregard (?:axiom|principle|rule|safety)/i, quick: true),
      # Block privilege escalation (inbound only)
      Rule.new(action: :block, direction: :in, pattern: /\bdoas\b/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /\bsudo\b/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /\bsu\s+-?\s/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /\bpfctl\s+-f\b/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /\brcctl\s+restart\b/, quick: true),
      # Block destructive operations (inbound only)
      Rule.new(action: :block, direction: :in, pattern: /\brm\s+-rf?\s+\//, quick: true),
      Rule.new(action: :block, direction: :in, pattern: />\s*\/dev\/[sh]da/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /DROP\s+TABLE/i, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /mkfs\./, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /dd\s+if=/, quick: true),
      # Pass with tag for review
      Rule.new(action: :pass, pattern: /escalation:/, quick: false, tag: :needs_review),
      # Default pass for clean content
      Rule.new(action: :pass, pattern: /.*/, quick: false),
    ].freeze

    MAX_OUTPUT_SIZE = 100_000

    class << self
      def evaluate(text, rules: DEFAULT_RULES, direction: :in)
        if text.length > MAX_OUTPUT_SIZE
          return { verdict: :block, reason: "Output too large: #{text.length} chars (max #{MAX_OUTPUT_SIZE})" }
        end

        rules.each do |rule|
          next if rule.direction && rule.direction != direction
          next unless text.match?(rule.pattern)

          return { verdict: :block, rule: rule, reason: "Blocked by rule: #{rule.pattern.source}" } if rule.action == :block
          return { verdict: :pass, tag: rule.tag } if rule.tag
          return { verdict: :pass } if rule.action == :pass
        end

        { verdict: :block, reason: "Default deny — no rule matched" }
      end

      def sanitize(agent_result, direction: :out)
        return Result.err("Agent returned error: #{agent_result.error}") if agent_result.err?

        output = agent_result.value
        text = output[:response] || output[:text] || output[:rendered] || ""

        verdict = evaluate(text, direction: direction)

        return Result.err("Agent output blocked: #{verdict[:reason]}") if verdict[:verdict] == :block

        clean_text = text.gsub(/```system.*?```/m, "[REDACTED SYSTEM BLOCK]")

        Result.ok(output.merge(text: clean_text, sanitized: true, firewall_tag: verdict[:tag]))
      end
    end
  end
end
