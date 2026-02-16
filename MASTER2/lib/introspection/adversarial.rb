# frozen_string_literal: true

module MASTER
  module Analysis
  class Introspection
    class << self
      # SECTION 5: Adversarial Questioning (original introspection)
      # ===================================================================

      def hostile_questions
        @hostile_questions ||= begin
          config = load_questions
          config.dig('hostile', 'questions') || default_hostile_questions
        end
      end

      def phase_reflections
        @phase_reflections ||= begin
          config = load_questions
          reflections = {}
          %w[discover analyze ideate design implement validate deliver learn].each do |phase|
            if config[phase]
              reflections[phase.to_sym] = config.dig(phase, 'introspection') ||
                                          config.dig(phase, 'purpose')
            end
          end
          reflections.empty? ? default_phase_reflections : reflections
        end
      end

      # Interrogate any input/output with hostile questions
      def interrogate(content, context: {})
        issues = []

        # Fast path: heuristic checks (no LLM cost)
        hostile_questions.each do |question|
          issue = fast_check(content, question)
          issues << issue if issue
        end

        # Phase-specific reflection if stage provided
        if context[:stage]
          reflection = phase_reflections[context[:stage].to_sym]
          if reflection
            issue = fast_check(content, reflection)
            issues << issue if issue
          end
        end

        {
          interrogated: true,
          issues: issues,
          passed: issues.empty?,
          severity: calculate_severity(issues),
          recommendation: recommendation(issues),
        }
      end

      # Deep interrogation with LLM (uses budget)
      def deep_interrogate(content, context: {})
        issues = []

        # Sample questions for cost efficiency
        questions = hostile_questions.sample(3)
        questions << phase_reflections[context[:stage].to_sym] if context[:stage]

        questions.compact.each do |question|
          result = ask_hostile(content, question)
          issues << result if result
        end

        {
          deep: true,
          issues: issues,
          passed: issues.empty?,
          severity: calculate_severity(issues),
        }
      end

      # Audit against axioms
      def audit(content, axioms: nil)
        axioms ||= DB.axioms
        violations = []

        axioms.each do |axiom|
          violation = check_axiom(content, axiom)
          violations << violation if violation
        end

        {
          audited: true,
          violations: violations,
          passed: violations.empty?,
          axioms_checked: axioms.size,
        }
      end

      # Full adversarial review: interrogate + enforcement
      # Simplified to use only Enforcement.check() (ONE_SOURCE compliance)
      def full_review(content, context: {})
        interrogation = interrogate(content, context: context)
        enforcement = Enforcement.check(content, filename: context[:filename] || "input")

        all_issues = interrogation[:issues] + enforcement[:violations]

        {
          passed: all_issues.empty?,
          interrogation: interrogation,
          enforcement: enforcement,
          total_issues: all_issues.size,
          severity: calculate_severity(all_issues),
          recommendation: recommendation(all_issues),
        }
      end
    end

    private

    class << self
      private
      # ===================================================================
      # PRIVATE HELPERS - Section 5 (Adversarial Questioning)
      # ===================================================================

      FAST_CHECKS = {
        /assumption.*wrong/i => {
          pattern: /\b(always|never|must|definitely|guaranteed)\b/i,
          issue: "Contains absolute language",
        },
        /hostile user/i => {
          pattern: /\b(password|secret|key|token|credential)\b/i,
          issue: "May expose sensitive information",
        },
        /edge case/i => {
          check: ->(c) { c.match?(/\bnil\b|\bnull\b/) && !c.match?(/\b(handle|check|guard|rescue)\b/i) },
          issue: "May not handle nil/null edge cases",
        },
        /simplest/i => {
          check: ->(c) { c.length > 5000 },
          issue: "Content very long - may not be simplest",
        },
        /regret/i => {
          pattern: /\b(TODO|FIXME|XXX|HACK|temporary|workaround)\b/i,
          issue: "Contains technical debt markers",
        },
        /who loses/i => {
          pattern: /\b(delete|remove|drop|disable|revoke)\b/i,
          issue: "Contains destructive operations",
        },
        /second-order/i => {
          check: ->(c) { c.scan(/\b(require|import|include|use)\b/).size > 10 },
          issue: "Many dependencies - consider cascading effects",
        },
        /security officer/i => {
          pattern: /\b(eval|exec|system|`[^`]+`|%x\{)/i,
          issue: "Contains code execution patterns",
        },
        /complexity hiding/i => {
          check: ->(c) { c.scan(/\bif\b|\bcase\b|\b\?\s*.*:/).size > 20 },
          issue: "High branching complexity",
        },
        /technical debt/i => {
          check: ->(c) { c.scan(/\b(TODO|FIXME|HACK|XXX|OPTIMIZE|REFACTOR)\b/i).size > 3 },
          issue: "Multiple technical debt markers",
        },
      }.freeze

      def fast_check(content, question)
        FAST_CHECKS.each do |q_pattern, check|
          next unless question.match?(q_pattern)

          triggered = check[:check]&.call(content) || (check[:pattern] && content.match?(check[:pattern]))
          return { question: question, issue: check[:issue] } if triggered
        end
        nil
      end

      def ask_hostile(content, question)
        prompt = <<~PROMPT
          HOSTILE QUESTION: #{question}

          CONTENT:
          #{content[0, 2000]}

          If genuine issue found, respond: ISSUE: [description]
          Otherwise respond: PASS
        PROMPT

        result = LLM.ask(prompt, stream: false)
        return nil unless result.ok?

        response = result.value[:content].to_s
        if response.include?("ISSUE:")
          { question: question, issue: response[/ISSUE:\s*(.+)/, 1] }
        else
          nil
        end
      end

      def check_axiom(content, axiom)
        id = axiom[:id] || axiom["id"]
        pattern = axiom[:pattern] || axiom["pattern"]

        if pattern && content.match?(Regexp.new(pattern, Regexp::IGNORECASE))
          return { axiom: id, issue: "Pattern violation" }
        end

        case id
        when "OMIT_WORDS"
          fillers = content.scan(/\b(just|really|very|basically|actually|literally|quite|rather)\b/i).size
          return { axiom: id, issue: "#{fillers} filler words" } if fillers > 5

        when "ACTIVE_VOICE"
          passive = content.scan(/\b(was|were|been|being)\s+\w+ed\b/i).size
          return { axiom: id, issue: "#{passive} passive constructions" } if passive > 3

        when "DRY"
          lines = content.lines.map(&:strip).reject(&:empty?)
          dups = lines.group_by(&:itself).select { |_, v| v.size > 2 && v.first.length > 30 }
          return { axiom: id, issue: "Repeated lines detected" } if dups.any?

        when "KISS"
          if content.scan(/\bclass\b/).size > 3 || content.scan(/\bmodule\b/).size > 3
            return { axiom: id, issue: "Too many classes/modules" }
          end

        when "FAIL_LOUD"
          if content.match?(/rescue\s*($|#|\n\s*end)/)
            return { axiom: id, issue: "Bare rescue swallows errors" }
          end
        end

        nil
      end

      def calculate_severity(issues)
        count = issues.size
        if count >= 5 then :critical
        elsif count >= 3 then :high
        elsif count >= 1 then :medium
        else :low
        end
      end

      def recommendation(issues)
        case calculate_severity(issues)
        when :critical then "Major issues - requires significant revision"
        when :high then "Notable issues - revision recommended"
        when :medium then "Minor issues - acceptable with acknowledgment"
        else "Passes adversarial review"
        end
      end

      def load_questions
        path = File.join(MASTER.root, 'data', 'questions.yml')
        YAML.safe_load_file(path, permitted_classes: [Symbol])
      rescue Errno::ENOENT
        {}
      end

      def default_hostile_questions
        [
          "What assumption here could be completely wrong?",
          "What would a hostile user do with this?",
          "What edge case would break this in production?",
          "Is this the simplest possible solution?",
          "What would I regret about this in 6 months?",
          "What am I not seeing?",
          "Who loses if this is implemented?",
          "What's the second-order effect?",
          "Is this solving the right problem or a symptom?",
          "What would the security officer veto here?",
          "Where is the complexity hiding?",
          "What would break if requirements changed 20%?",
          "Where is technical debt accumulating?"
        ]
      end

      def default_phase_reflections
        {
          intake: "Did I understand the actual intent, not just the words?",
          compress: "Did I lose essential meaning in compression?",
          guard: "Did I block something legitimate?",
          route: "Did I pick the right model for this task?",
          council: "Did the council debate the real issues?",
          ask: "Did the LLM answer what was asked?",
          lint: "Did I enforce axioms consistently?",
          render: "Is the output clear to the user?"
        }
      end
    end
  end
  end
end
