# frozen_string_literal: true

module MASTER
  class AgentFirewall
    Rule = Struct.new(:action, :direction, :pattern, :quick, :tag, keyword_init: true)

    # pf-style rules: block/pass, in/out, pattern match, quick (first match wins), tag for review
    DEFAULT_RULES = [
      # Block prompt injection — quick (first match stops evaluation)
      Rule.new(action: :block, direction: :in, pattern: /ignore (?:all )?(?:previous|above|prior) instructions/i, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /you are now/i, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /new system prompt/i, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /forget (?:everything|all|your)/i, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /override (?:axiom|principle|rule)/i, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /disregard (?:axiom|principle|rule|safety)/i, quick: true),

      # Block privilege escalation from children
      Rule.new(action: :block, direction: :in, pattern: /\bdoas\b/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /\bsudo\b/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /\bsu\s+-?\s/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /\bpfctl\s+-f\b/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /\brcctl\s+restart\b/, quick: true),

      # Block dangerous commands
      Rule.new(action: :block, direction: :in, pattern: /\brm\s+-rf?\s+\//, quick: true),
      Rule.new(action: :block, direction: :in, pattern: />\s*\/dev\/[sh]da/, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /DROP\s+TABLE/i, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /mkfs\./, quick: true),
      Rule.new(action: :block, direction: :in, pattern: /dd\s+if=/, quick: true),

      # Tag escalation requests for parent review
      Rule.new(action: :pass, direction: :in, pattern: /escalation:/, quick: false, tag: :needs_review),

      # Default pass for clean output (last rule)
      Rule.new(action: :pass, direction: :out, pattern: /.*/, quick: false),
    ].freeze

    MAX_OUTPUT_SIZE = 100_000

    def self.evaluate(text, rules: DEFAULT_RULES)
      # Size check
      return { verdict: :block, reason: "Output too large: #{text.length} chars (max #{MAX_OUTPUT_SIZE})" } if text.length > MAX_OUTPUT_SIZE

      rules.each do |rule|
        next unless text.match?(rule.pattern)

        if rule.action == :block
          return { verdict: :block, rule: rule, reason: "Blocked by rule: #{rule.pattern.source}" }
        end

        if rule.tag
          return { verdict: :pass, tag: rule.tag }
        end

        # Pass action
        return { verdict: :pass } if rule.action == :pass
      end

      # If no rules matched, default deny
      { verdict: :block, reason: "Default deny — no rule matched" }
    end

    # Sanitize agent result before parent trusts it
    def self.sanitize(agent_result)
      return Result.err("Agent returned error: #{agent_result.error}") if agent_result.err?

      output = agent_result.value
      text = output[:response] || output[:text] || output[:rendered] || ""

      verdict = evaluate(text)

      if verdict[:verdict] == :block
        return Result.err("Agent output blocked: #{verdict[:reason]}")
      end

      # Strip system-prompt-like blocks
      clean_text = text.gsub(/```system.*?```/m, "[REDACTED SYSTEM BLOCK]")

      Result.ok(output.merge(text: clean_text, sanitized: true, firewall_tag: verdict[:tag]))
    end
  end
end
