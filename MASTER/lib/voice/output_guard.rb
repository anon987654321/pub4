# frozen_string_literal: true

module Master
  module Voice
    # G09/G10: enforce preserve rules and require_evidence on MASTER's own output.
    class OutputGuard
      COLLAPSED_DIAGNOSTIC_LINE_LENGTH = 120
      COMPLETION_CLAIM = /\b(fixed|completed|done|applied|updated|removed|added|wired|implemented)\b/i
      MODIFICATION_CLAIM = /\b(changed|modified|edited|patched|replaced|refactored)\b/i
      EVIDENCE_MARKERS = [
        /```/,
        /^diff --git/m,
        /^@@ /m,
        /^\+/m,
        /sha-?256/i,
        /\$ .+/,
        /exit code:?\s*\d/i,
        /scan:/i,
        /violation/i,
      ].freeze

      def initialize(rules: nil)
        @rules = rules || Ground::Rules.new
        @preserve = @rules.preserve
        soul = @rules.data(:soul) || {}
        # Under "absolute", where soul.yml actually nests it. There is no
        # top-level anti_simulation key, so this dug nothing and @evidence has
        # always been {} — the evidence contract is enforced by the hardcoded
        # regexes further down instead. prompt_filter.rb digs the same block
        # with the "absolute" prefix, which is what confirms the shape.
        @evidence = soul.dig("absolute", "anti_simulation", "require_evidence") || {}
      end

      def sanitize(text, context: :routine)
        return text.to_s if text.to_s.empty?

        out = text.to_s
        out = preserve_diagnostic_structure(out) if diagnostic_context?(context)
        out = append_evidence_hint(out, context) unless evidence_present?(out, context)
        out
      end

      def validate(text, context: :routine)
        issues = []
        issues << "boot message must remain 5-line dmesg style" if context == :boot && boot_message_collapsed?(text)
        issues << "diagnostic output collapsed" if diagnostic_context?(context) && collapsed_diagnostic?(text)
        issues << "help output missing syntax/example detail" if context == :help && incomplete_help?(text)
        issues << "minimize rule misapplied to diagnostic output" if minimize_misapplied?(text)
        issues << "modification claim without diff" if modification_claim?(text) && !diff_evidence?(text)
        issues << "completion claim without command output" if completion_claim?(text) && !command_evidence?(text)
        issues.empty? ? Result.ok(text) : Result.err(issues.join("; "), category: :axiom_violation)
      end

      private

      def diagnostic_context?(context)
        context == :diagnostic || context == :scan_report
      end

      def preserve_diagnostic_structure(text)
        # Read as a number from the key that holds one. This used to run /\d+/
        # over `diagnostic_output`, whose value is a sentence with no digits, so
        # the match was always nil and the floor was permanently the fallback.
        min_lines = (@preserve["diagnostic_min_lines"] || @preserve[:diagnostic_min_lines]).to_i
        min_lines = 2 if min_lines < 2
        lines = text.lines
        return text if lines.size >= min_lines
        text
      end

      def collapsed_diagnostic?(text)
        lines = text.to_s.lines.map(&:strip).reject(&:empty?)
        return false if lines.size >= 2
        lines.first.to_s.length > COLLAPSED_DIAGNOSTIC_LINE_LENGTH
      end

      def boot_message_collapsed?(text)
        lines = text.to_s.lines.map(&:strip).reject(&:empty?)
        lines.size != 5 || lines.any? { |line| !line.start_with?("master:") }
      end

      def incomplete_help?(text)
        lines = text.to_s.lines.map(&:strip).reject(&:empty?)
        return true if lines.size < 3

        command_line = lines.any? { |line| line.start_with?("/") && line.include?(" - ") }
        syntax_line = lines.any? { |line| line.start_with?("/") && line.match?(/\s|\[/) }
        command_line && syntax_line ? false : true
      end

      def minimize_misapplied?(text)
        text.to_s.match?(/minimi[sz]e.*diagnostic output|diagnostic output.*minimi[sz]e/i)
      end

      def modification_claim?(text)
        text.to_s.match?(MODIFICATION_CLAIM)
      end

      def completion_claim?(text)
        text.to_s.match?(COMPLETION_CLAIM)
      end

      def diff_evidence?(text)
        text.include?("```") || text.match?(/^diff --git/m) || text.match?(/^@@ /m)
      end

      def command_evidence?(text)
        EVIDENCE_MARKERS.any? { |re| text.match?(re) }
      end

      def evidence_present?(text, context)
        case context
        when :modification then diff_evidence?(text)
        when :completion then command_evidence?(text)
        else true
        end
      end

      # Derived from soul.yml, not restating it. @evidence was dug from a key
      # that does not exist and was therefore always {}, so these two strings
      # were the whole contract — a hardcoded copy of the constitution sitting
      # a few lines below the read meant to supply it. The fallbacks keep the
      # previous behaviour if the key is ever absent.
      def append_evidence_hint(text, context)
        requirement = @evidence[context.to_s] ||
                      { modification: "show unified diff", completion: "show command output" }[context]
        return text unless requirement

        hint = "\n[evidence required: #{requirement}]"
        text.include?("[evidence required") ? text : "#{text}#{hint}"
      end
    end
  end
end
