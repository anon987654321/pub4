# frozen_string_literal: true

module MASTER
  # Introspection - LLM self-examination and hostile questioning
  class Introspection
    HOSTILE_QUESTIONS = [
      "What assumption here could be completely wrong?",
      "What would a senior engineer critique first?",
      "Where is the complexity hiding?",
      "What edge case will fail in production?",
      "Is this solving the real problem or a symptom?",
      "What's the simplest thing that could work instead?",
      "What would break if requirements changed 20%?",
      "Where is technical debt accumulating?",
      "What are you avoiding thinking about?"
    ].freeze

    PHASE_REFLECTIONS = {
      discover: "What did I miss? What assumptions did I make?",
      analyze:  "Did I understand the real constraints?",
      design:   "Is this overengineered? Underengineered?",
      implement: "What shortcuts did I take?",
      validate: "Did I test the right things?"
    }.freeze

    def initialize(llm: LLM)
      @llm = llm
    end

    def reflect_on_phase(phase, summary)
      reflection = PHASE_REFLECTIONS[phase.to_sym]
      return nil unless reflection

      prompt = <<~PROMPT
        You completed #{phase.upcase}. Summary:
        #{summary}

        Reflect: #{reflection}
        Be specific. Name files, decisions, tradeoffs.
      PROMPT

      chat = @llm.chat(model: @llm.pick)
      chat.ask(prompt).content
    rescue => e
      "Reflection failed: #{e.message}"
    end

    def hostile_question(decision, context = nil)
      question = HOSTILE_QUESTIONS.sample

      prompt = <<~PROMPT
        DECISION: #{decision}
        #{"CONTEXT: #{context}" if context}

        HOSTILE QUESTION: #{question}

        Answer honestly. No defensive platitudes.
      PROMPT

      chat = @llm.chat(model: @llm.pick)
      chat.ask(prompt).content
    rescue => e
      "Question failed: #{e.message}"
    end

    def self_examine(code, filename: nil)
      prompt = <<~PROMPT
        Examine this code as a hostile reviewer:
        #{"FILE: #{filename}" if filename}

        ```
        #{code[0, 3000]}
        ```

        1. What's the worst bug hiding here?
        2. What will the next developer curse you for?
        3. What would you delete entirely?
        4. What's missing that should be obvious?
      PROMPT

      chat = @llm.chat(model: @llm.pick)
      chat.ask(prompt).content
    rescue => e
      "Examination failed: #{e.message}"
    end
  end
end
