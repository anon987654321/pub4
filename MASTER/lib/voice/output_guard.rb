# frozen_string_literal: true

module Master
  module Voice
    # G09/G10: enforce preserve rules and require_evidence on MASTER's own output.
    class OutputGuard
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
        /violation/i
      ].freeze

      def initialize(rules: nil)
        @rules = rules || Ground::Rules.new
        @preserve = @rules.preserve
        @evidence = @rules.data(:soul).dig("anti_simulation", "require_evidence") || {}
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
        min_lines = (@preserve["diagnostic_output"] || @preserve[:diagnostic_output]).to_s[/\d+/]&.to_i
        min_lines = 2 if min_lines.nil? || min_lines < 2
        lines = text.lines
        return text if lines.size >= min_lines
        text
      end

      def collapsed_diagnostic?(text)
        lines = text.to_s.lines.map(&:strip).reject(&:empty?)
        return false if lines.size >= 2
        lines.first.to_s.length > 120
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

      def append_evidence_hint(text, context)
        hint = case context
               when :modification then "\n[evidence required: show unified diff]"
               when :completion then "\n[evidence required: show command output]"
               else return text
               end
        text.include?("[evidence required") ? text : "#{text}#{hint}"
      end
    end
  end
end
