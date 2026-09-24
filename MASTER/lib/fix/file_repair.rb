# frozen_string_literal: true

module Master
  module Fix
    # One repair per file: every finding the stream may repair in the file, in
    # one prompt, one candidate and one verdict. RuleLoop asks per rule, after
    # an architecture plan for any file over 200 lines, with three candidates,
    # and repairs one finding per file and rule a pass, each prompt carrying the
    # whole 30 KB constitution. Measured on /fix MASTER: about four calls a
    # finding, thirty-odd files an hour. This keeps RuleLoop's extraction,
    # verifier, apply guard, tests and commit, and changes only what it asks.
    class FileRepair < RuleLoop
      Scope = Data.define(:id, :description)

      GOLDEN = "Golden rule: preserve, then improve, never break. Make the smallest change " \
               "that removes each finding; touch nothing else."

      def initialize(findings:, rules:, agent:, scanner:, root:, **options)
        @notes = rules.to_h { |rule| [rule.id.to_s, rule.respond_to?(:description) ? rule.description.to_s : ""] }
        @findings = findings
        ids = findings.map { |finding| finding[:rule].to_s }.uniq
        super(rule: Scope.new(id: ids.join("+"), description: "file repair"), agent:, scanner:, root:, **options)
      end

      # The findings a model may take on: none that waits for a person or that
      # the scanner's confidence gate refuses.
      def repairable
        @findings.reject { |finding| needs_a_person?(finding) }.select { |finding| autofix_allowed?(finding) }
      end

      def scope = @rule

      def run(path)
        @findings = repairable
        return { fixed: 0, status: :skipped, breakdown: { skip_confidence: 1 } } if @findings.empty?

        run_once([path], external_violations: [summary(path)])
      end

      private

      def summary(path)
        first = @findings.min_by { |finding| finding[:line].to_i }
        { rule: @rule.id, file: path, line: first[:line], severity: :warning,
          message: @findings.map { |finding| "#{finding[:rule]} line #{finding[:line]}" }.join("; ") }
      end

      # Straight to the file: no architecture plan, and one candidate.
      def request_fix(violation)
        path = violation[:file]
        src = File.read(path, encoding: "UTF-8")
        return diff_fix(violation:, src:, path:) if src.bytesize > PatchApplier::DIFF_THRESHOLD

        genetic_fix(violation:, src:, path:)
      end

      def genetic_autofix_candidates = 1

      def build_prompt_for(violation:, src:, path:, style: :file)
        ctx = prompt_context_for(violation:, path:, style:)
        <<~PROMPT
          #{GOLDEN}
          #{rule_notes}

          File: #{File.basename(path)} (#{ctx[:lang]})
          Findings. Repair each one that is real; leave any you judge a false positive as it is:
          #{finding_lines}

          #{ctx[:action]}

          ```#{ctx[:lang]}
          #{src}
          ```
        PROMPT
      end

      def rule_notes
        @findings.map { |finding| finding[:rule].to_s }.uniq
                 .map { |id| "- #{id}: #{@notes[id].to_s.empty? ? "see the finding" : @notes[id]}" }.join("\n")
      end

      def finding_lines
        lines = @findings.sort_by { |finding| finding[:line].to_i }.map do |finding|
          hint = finding[:fix].to_s.strip
          "- line #{finding[:line]}, #{finding[:rule]}: #{finding[:message]}#{" (how: #{hint})" unless hint.empty?}"
        end
        lines.join("\n")
      end

      # Learnings are kept per rule, and a file repair spans several.
      def record_outcomes(*) = nil
    end
  end
end
