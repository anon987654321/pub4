# frozen_string_literal: true

module MASTER
  # ProblemSolver: 5+ fix approaches per bug, hostile questioning, systematic debugging
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
      surgical:   [1, "Minimal change to exact broken line",           "Root cause clear, single failure point"],
      defensive:  [2, "Add guards, nil checks, validations",           "Input/state unpredictable"],
      refactor:   [3, "Restructure to eliminate the bug class",        "Code smell enabled the bug"],
      workaround: [2, "Route around it, don't touch it",               "Too risky to modify, deadline"],
      rewrite:    [4, "Rewrite function from scratch",                 "Faster to rewrite than understand"],
      rollback:   [1, "Git revert to last good state, redo carefully", "Recent regression, known good exists"],
      config:     [1, "Fix in env/config, not code",                   "Environment-specific problem"]
    }.freeze

    PROMPT = <<~P.freeze
      You are a senior debugger with 20 years experience. Analyze this bug systematically.

      ERROR/SYMPTOMS:
      {{ERROR}}

      CODE CONTEXT:
      {{CODE}}

      Provide analysis in this exact format:

      ROOT: [One sentence explaining WHY this happens - the actual root cause, not symptoms]
      
      DOUBT: [Challenge your own analysis - what could be wrong about your diagnosis?]

      FIXES (ranked from safest/minimal to most invasive):
      1.SURGICAL: [Exact minimal change - line number if possible, single point fix]
      2.DEFENSIVE: [Guards, nil checks, validations to add around the problem]
      3.REFACTOR: [Structural improvement that eliminates this class of bug]
      4.WORKAROUND: [Alternative approach that avoids the broken code entirely]
      5.REWRITE: [If code is incomprehensible, provide clean rewrite]

      PICK: [Which fix you recommend and why - consider risk, time, likelihood of success]
      
      VERIFY: [Exact steps to confirm the fix works - test commands, assertions, edge cases]
      
      SIMILAR: [Other files/functions where this same bug pattern might exist]
    P

    class << self
      def analyze(error:, code: nil, file: nil, llm: nil)
        llm ||= LLM.new
        ctx = file && File.exist?(file) ? File.read(file)[0..3000] : code.to_s[0..3000]
        prompt = PROMPT.sub('{{ERROR}}', error.to_s[0..1000]).sub('{{CODE}}', ctx)

        Dmesg.log("solver0", parent: "debug", message: error.to_s[0..40]) rescue nil

        result = llm.chat(prompt, tier: :strong)
        return Result.err("Analysis failed") unless result.ok?
        parse(result.value)
      end

      def quick(error, llm: nil)
        llm ||= LLM.new
        result = llm.chat("Error: #{error[0..500]}\n\n5 fixes, one line each:\n1.", tier: :fast)
        return [] unless result.ok?
        result.value.lines.grep(/^\d+\./).map { |l| l.sub(/^\d+\.\s*/, '').strip }
      end

      def hostile = HOSTILE.sample

      def challenge(fix, llm: nil)
        llm ||= LLM.new
        result = llm.chat("Fix: #{fix[0..300]}\n\nIn 2 sentences: what could go wrong, what's safer?", tier: :fast)
        result.ok? ? result.value : nil
      end

      def suggest(symptoms)
        s = symptoms.to_s.downcase
        keys = if s.match?(/nil|undefined/) then [:defensive, :surgical]
               elsif s.match?(/timeout|slow/) then [:config, :workaround]
               elsif s.match?(/regression|worked/) then [:rollback, :surgical]
               elsif s.match?(/spaghetti|mess/) then [:rewrite, :refactor]
               else [:surgical, :defensive, :refactor]
               end
        keys.map { |k| { name: k, risk: FIXES[k][0], desc: FIXES[k][1], when: FIXES[k][2] } }
      end

      def format_fixes(list = FIXES)
        list.map { |k, (r, d, w)| "#{k.upcase} (risk #{r}/5): #{d}\n  When: #{w}" }.join("\n\n")
      end

      private

      def parse(text)
        { root: grab(text, 'ROOT'), doubt: grab(text, 'DOUBT'),
          fixes: { surgical: grab(text, 'SURGICAL'), defensive: grab(text, 'DEFENSIVE'),
                   refactor: grab(text, 'REFACTOR'), workaround: grab(text, 'WORKAROUND'),
                   rewrite: grab(text, 'REWRITE') },
          pick: grab(text, 'PICK'), verify: grab(text, 'VERIFY'), similar: grab(text, 'SIMILAR'), raw: text }
      end

      def grab(text, key)
        text.match(/(?:#{key}|\d+\.#{key}):\s*(.+?)(?=\n[A-Z]+:|\n\d+\.[A-Z]+:|\z)/im)&.[](1)&.strip
      end
    end
  end
end
