# frozen_string_literal: true

module MASTER
  # ProblemSolver - Systematic 5-fix approach to debugging
  module ProblemSolver
    extend self

    HOSTILE = [
      "What if the bug is in a different file?",
      "What if your fix creates a worse bug?",
      "What if the 'bug' is correct behavior?",
      "What if 5 other places have this bug?",
      "What if it worked yesterday—what changed?",
      "What if the error message lies?",
      "What if it's data, not code?",
      "What if it only works on your machine?",
      "What if you're fixing symptoms, not cause?",
      "What if deleting the feature is simpler?"
    ].freeze

    FIXES = {
      surgical:   { effort: 1, desc: "Minimal change to exact broken line" },
      defensive:  { effort: 2, desc: "Add guards, nil checks, validations" },
      refactor:   { effort: 3, desc: "Restructure to eliminate bug class" },
      workaround: { effort: 2, desc: "Route around it, don't touch it" },
      rewrite:    { effort: 4, desc: "Rewrite function from scratch" }
    }.freeze

    PROMPT = <<~P.freeze
      You are a senior debugger. Analyze this bug systematically.

      ERROR: {{ERROR}}
      CODE: {{CODE}}

      Provide:
      ROOT: [Why this happens - root cause, not symptoms]
      DOUBT: [Challenge your diagnosis - what could be wrong?]

      FIXES (safest to most invasive):
      1. SURGICAL: [Exact minimal change]
      2. DEFENSIVE: [Guards and validations]
      3. REFACTOR: [Structural fix]
      4. WORKAROUND: [Avoid the broken code]
      5. REWRITE: [Clean rewrite if needed]

      PICK: [Recommended fix and why]
      VERIFY: [How to confirm fix works]
      SIMILAR: [Other places with same bug pattern]
    P

    def analyze(error:, code:, llm: LLM)
      prompt = PROMPT.gsub("{{ERROR}}", error.to_s[0, 1000])
                     .gsub("{{CODE}}", code.to_s[0, 3000])

      result = llm.ask(prompt, tier: :fast)
      if result.ok?
        {
          analysis: result.value[:content],
          hostile_check: HOSTILE.sample,
          fixes: FIXES.keys
        }
      else
        { error: result.error }
      end
    rescue StandardError => e
      { error: e.message }
    end

    def hostile_check
      HOSTILE.sample
    end
  end
end
