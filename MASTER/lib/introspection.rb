# frozen_string_literal: true

module MASTER
  # LLM introspection and hostile questioning
  # Forces the system to examine its own reasoning and defend principles
  class Introspection
    MAX_SUMMARY_LENGTH = 200

    HOSTILE_QUESTIONS = [
      "What assumption here could be completely wrong?",
      "What would a senior engineer critique first?",
      "Where is the complexity hiding that will bite us later?",
      "What edge case will this fail on in production?",
      "Is this solving the real problem or a symptom?",
      "What's the simplest thing that could work instead?",
      "Would you be proud to show this code in an interview?",
      "What would break if requirements changed 20%?",
      "Where is the technical debt accumulating?",
      "What's the one thing you're avoiding thinking about?"
    ].freeze

    PHASE_REFLECTIONS = {
      discover: "What did I miss? What assumptions did I make?",
      analyze: "Did I understand the real constraints? What's still unclear?",
      ideate: "Did I explore enough options? Was I too conservative?",
      design: "Is this overengineered? Is it underengineered?",
      implement: "What shortcuts did I take? What would I do differently?",
      validate: "Did I test the right things? What's still risky?",
      deliver: "Is this truly ready? What will the user actually experience?"
    }.freeze

    def initialize(llm)
      @llm = llm
    end

    # End-of-phase introspection
    def reflect_on_phase(phase, work_summary)
      reflection_prompt = PHASE_REFLECTIONS[phase.to_sym]
      return nil unless reflection_prompt

      prompt = <<~PROMPT
        You just completed the #{phase.upcase} phase. Here's what you did:

        #{work_summary}

        Now reflect honestly: #{reflection_prompt}

        Be specific. Name files, decisions, tradeoffs. No vague platitudes.
        If everything is actually fine, say so—but prove it.
      PROMPT

      @llm.chat(prompt, max_tokens: 500)
    end

    # Hostile questioning for any principle or decision
    def hostile_question(principle_or_decision, context = nil)
      question = HOSTILE_QUESTIONS.sample

      prompt = <<~PROMPT
        PRINCIPLE/DECISION: #{principle_or_decision}
        #{context ? "\nCONTEXT: #{context}" : ""}

        HOSTILE QUESTION: #{question}

        Answer honestly and specifically. If the principle is flawed, say so.
        If you can't defend it, admit that. No corporate hedging.
      PROMPT

      {
        question: question,
        response: @llm.chat(prompt, max_tokens: 400)
      }
    end

    # Full hostile audit of all principles
    def audit_principles(principles_dir)
      results = []

      Dir.glob(File.join(principles_dir, "*.md")).each do |path|
        name = File.basename(path, ".md")
        content = File.read(path)

        # Extract the core principle (first non-empty line after title)
        lines = content.lines.reject { |l| l.strip.empty? || l.start_with?("#") }
        core = lines.first&.strip || content[0..MAX_SUMMARY_LENGTH]

        result = hostile_question(core, "From principle file: #{name}.md")
        results << {
          principle: name,
          core: core,
          question: result[:question],
          response: result[:response]
        }
      end

      results
    end

    # Self-examination after any significant action
    def examine(action_description, outcome)
      prompt = <<~PROMPT
        ACTION: #{action_description}
        OUTCOME: #{outcome}

        Examine this honestly:
        1. Did the action achieve its goal?
        2. What unintended effects might it have?
        3. What would you do differently next time?
        4. Rate your confidence in this outcome: LOW / MEDIUM / HIGH

        Be specific. One paragraph max.
      PROMPT

      @llm.chat(prompt, max_tokens: 300)
    end

    # Pre-action sanity check
    def sanity_check(proposed_action)
      prompt = <<~PROMPT
        PROPOSED ACTION: #{proposed_action}

        Before doing this, answer:
        1. Is this reversible? If not, what's the rollback plan?
        2. What's the worst case if this goes wrong?
        3. Is there a simpler way to achieve the same goal?
        4. Should you proceed? YES / NO / WAIT

        One sentence per answer.
      PROMPT

      @llm.chat(prompt, max_tokens: 200)
    end

    # Adversarial self-review of generated code
    def review_own_code(code, purpose)
      prompt = <<~PROMPT
        You just wrote this code for: #{purpose}

        ```
        #{code}
        ```

        Now attack it. Find:
        1. The most likely bug
        2. The worst code smell
        3. The missing error handling
        4. The performance issue that will emerge at scale

        If the code is actually solid, explain why for each point.
        No softening language. Be harsh but accurate.
      PROMPT

      @llm.chat(prompt, max_tokens: 500)
    end
  end
end
