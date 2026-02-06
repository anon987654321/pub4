# frozen_string_literal: true

module MASTER
  # ProblemSolver - 5+ fix approaches per bug, hostile questioning, systematic debugging
  # Based on BUG_HUNTING_GUIDE.md methodology
  module ProblemSolver
    extend self

    # Hostile questions to challenge assumptions
    HOSTILE_QUESTIONS = [
      "What if the bug is in a completely different file than you think?",
      "What if your fix introduces a worse bug?",
      "What if the 'bug' is actually correct behavior you don't understand?",
      "What if there are 5 other places with the same bug?",
      "What if this worked yesterday - what changed?",
      "What if the error message is lying to you?",
      "What if it's a data problem, not a code problem?",
      "What if it works on your machine but nowhere else?",
      "What if you're solving the symptom, not the cause?",
      "What if the simplest fix is to delete the feature?"
    ].freeze

    # Fix approach templates ranked by safety
    FIX_APPROACHES = {
      surgical: {
        name: "Surgical Fix",
        risk: 1,
        desc: "Minimal change, fix only the exact line causing the issue",
        when: "Root cause is clear, single point of failure"
      },
      defensive: {
        name: "Defensive Fix", 
        risk: 2,
        desc: "Add guards, validations, nil checks around the problem area",
        when: "Input/state can be unpredictable"
      },
      refactor: {
        name: "Refactor Fix",
        risk: 3,
        desc: "Restructure the problematic code to eliminate the bug class",
        when: "Code smell enabled the bug, fix the smell"
      },
      workaround: {
        name: "Workaround",
        risk: 2,
        desc: "Don't fix the bug, route around it",
        when: "Touching the code is too risky, deadline pressure"
      },
      rewrite: {
        name: "Targeted Rewrite",
        risk: 4,
        desc: "Rewrite the function/method from scratch",
        when: "Code is incomprehensible, faster to rewrite than understand"
      },
      rollback: {
        name: "Rollback + Redo",
        risk: 1,
        desc: "Git revert to last working state, redo changes carefully",
        when: "Recent regression, known good state exists"
      },
      config: {
        name: "Configuration Fix",
        risk: 1,
        desc: "Fix in config/env, not code",
        when: "Problem is environment-specific"
      }
    }.freeze

    ANALYSIS_PROMPT = <<~PROMPT.freeze
      You are a senior debugger. Analyze this bug systematically.

      ERROR/SYMPTOMS:
      {{ERROR}}

      CODE CONTEXT:
      {{CODE}}

      Provide analysis in this exact format:

      ROOT_CAUSE: [One sentence explaining WHY this happens]
      
      HOSTILE_CHECK: [Challenge your own analysis - what could be wrong about it?]

      FIXES (ranked safest to riskiest):
      1. SURGICAL: [exact change, line number if possible]
      2. DEFENSIVE: [guards/checks to add]
      3. REFACTOR: [structural improvement]
      4. WORKAROUND: [alternative approach]
      5. REWRITE: [if needed, new implementation]

      RECOMMENDED: [which fix and why]
      
      VERIFICATION: [how to confirm the fix works]
      
      SIMILAR_BUGS: [other places this pattern might exist]
    PROMPT

    class << self
      def analyze(error:, code: nil, file: nil, llm: nil)
        llm ||= LLM.new
        
        code_context = if file && File.exist?(file)
          File.read(file)[0..3000]
        else
          code.to_s[0..3000]
        end

        prompt = ANALYSIS_PROMPT
          .sub('{{ERROR}}', error.to_s[0..1000])
          .sub('{{CODE}}', code_context)

        Dmesg.log("solver0", parent: "debug", message: "analyzing: #{error.to_s[0..40]}") rescue nil

        result = llm.chat(prompt, tier: :strong)
        return Result.err("Analysis failed") unless result.ok?

        parse_analysis(result.value)
      end

      def quick_fixes(error, llm: nil)
        llm ||= LLM.new
        
        prompt = <<~PROMPT
          Error: #{error[0..500]}
          
          Give me 5 possible fixes, one line each, ranked by likelihood:
          1. 
          2.
          3.
          4.
          5.
        PROMPT

        result = llm.chat(prompt, tier: :fast)
        return [] unless result.ok?

        result.value.lines
          .grep(/^\d+\./)
          .map { |l| l.sub(/^\d+\.\s*/, '').strip }
      end

      def hostile_question
        HOSTILE_QUESTIONS.sample
      end

      def challenge(proposed_fix, llm: nil)
        llm ||= LLM.new
        
        prompt = <<~PROMPT
          Someone proposes this fix: #{proposed_fix[0..500]}
          
          Play devil's advocate. In 2-3 sentences:
          1. What could go wrong with this fix?
          2. What are they probably not considering?
          3. What's a safer alternative?
        PROMPT

        result = llm.chat(prompt, tier: :fast)
        result.ok? ? result.value : nil
      end

      def suggest_approach(symptoms)
        # Match symptoms to best approach
        symptoms_lower = symptoms.to_s.downcase

        if symptoms_lower.include?('nil') || symptoms_lower.include?('undefined')
          [:defensive, :surgical]
        elsif symptoms_lower.include?('timeout') || symptoms_lower.include?('slow')
          [:config, :workaround]
        elsif symptoms_lower.include?('regression') || symptoms_lower.include?('worked before')
          [:rollback, :surgical]
        elsif symptoms_lower.include?('incomprehensible') || symptoms_lower.include?('spaghetti')
          [:rewrite, :refactor]
        else
          [:surgical, :defensive, :refactor]
        end.map { |k| FIX_APPROACHES[k] }
      end

      def format_approaches(approaches = nil)
        approaches ||= FIX_APPROACHES.values
        
        approaches.map do |a|
          "#{a[:name]} (risk: #{a[:risk]}/5)\n  #{a[:desc]}\n  When: #{a[:when]}"
        end.join("\n\n")
      end

      private

      def parse_analysis(text)
        {
          root_cause: extract_section(text, 'ROOT_CAUSE'),
          hostile_check: extract_section(text, 'HOSTILE_CHECK'),
          fixes: {
            surgical: extract_section(text, 'SURGICAL'),
            defensive: extract_section(text, 'DEFENSIVE'),
            refactor: extract_section(text, 'REFACTOR'),
            workaround: extract_section(text, 'WORKAROUND'),
            rewrite: extract_section(text, 'REWRITE')
          },
          recommended: extract_section(text, 'RECOMMENDED'),
          verification: extract_section(text, 'VERIFICATION'),
          similar_bugs: extract_section(text, 'SIMILAR_BUGS'),
          raw: text
        }
      end

      def extract_section(text, name)
        # Match "NAME: content" or "N. NAME: content"
        match = text.match(/(?:#{name}|\d+\.\s*#{name}):\s*(.+?)(?=\n[A-Z_]+:|\n\d+\.\s*[A-Z]+:|\z)/im)
        match ? match[1].strip : nil
      end
    end
  end
end
