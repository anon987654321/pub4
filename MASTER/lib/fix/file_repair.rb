# frozen_string_literal: true

module Master
  module Fix
    # One repair per file: every finding the stream may repair in the file, in
    # one prompt, one candidate and one verdict. RepairLoop asks per rule, after
    # an architecture plan for any file over 200 lines, with three candidates,
    # and repairs one finding per file and rule a pass, each prompt carrying the
    # whole 30 KB constitution. Measured on /fix MASTER: about four calls a
    # finding, thirty-odd files an hour. This keeps RepairLoop's extraction,
    # verifier, apply guard, tests and commit, and changes only what it asks.
    class FileRepair < RepairLoop
      Scope = Data.define(:id, :description)

      GOLDEN = "Golden rule: preserve, then improve, never break. Make the smallest change " \
               "that removes each finding; touch nothing else."

      def initialize(findings:, rules:, agent:, scanner:, root:, **options)
        @notes = rules.to_h { |rule| [rule.id.to_s, rule.respond_to?(:description) ? rule.description.to_s : ""] }
        @findings = findings
        ids = findings.map { |finding| finding[:law].to_s }.uniq
        super(law: Scope.new(id: ids.join("+"), description: "file repair"), agent:, scanner:, root:, **options)
      end

      # The findings a model may take on: none that waits for a person or that
      # the scanner's confidence gate refuses.
      def repairable
        @findings.reject { |finding| needs_a_person?(finding) }.select { |finding| autofix_allowed?(finding) }
      end

      def scope = @law

      # The rules this repair put to the model, once run has filtered out what
      # waits for a person or fails the confidence gate.
      def asked_rules
        repairable.map { |finding| finding[:law].to_s }.uniq
      end

      def run(path)
        @findings = repairable
        return { fixed: 0, status: :skipped, breakdown: { skip_confidence: 1 } } if @findings.empty?

        run_once([path], external_violations: [summary(path)])
      end

      private

      def summary(path)
        first = @findings.min_by { |finding| finding[:line].to_i }
        { law: @law.id, file: path, line: first[:line], severity: :warning,
          message: @findings.map { |finding| "#{finding[:law]} line #{finding[:line]}" }.join("; ") }
      end

      # Straight to the finding: no architecture plan, one request. The model sees
      # each failing line with CONTEXT_LINES around it, not the file, and answers
      # with a minimal unified diff; a whole-file rewrite is what the verifier
      # kept refusing on 2026-10-12.
      def request_fix(violation)
        path = violation[:file]
        src = File.read(path, encoding: "UTF-8")
        excerpt_fix(src:, path:)
      end

      def scope_lines(_violation) = @findings.map { |finding| finding[:line].to_i }

      CONTEXT_LINES = 40

      def excerpt_fix(src:, path:)
        prompt = excerpt_prompt(src, path)
        MAX_FIX_RETRIES.times do |attempt|
          wait_before_retry(attempt, rule: @law.id, file: path, mode: :excerpt)
          response = ask_agent(prompt, image: @visual_image).to_s
          return RunLedger.declined("model_said_unchanged", file: path, law: @law.id) if response.strip == "UNCHANGED"
          return RunLedger.declined("empty_reply", file: path, law: @law.id) if response.strip.empty?

          result = PatchApplier.apply(src, diff_of(response))
          return result.source if result.is_a?(PatchApplier::Success)

          RunLedger.declined("patch_rejected", file: path, law: @law.id, detail: result.reason)
          @bus&.publish("repair_loop:edit_format_fallback", rule: @law.id, file: path, reason: result.reason.to_s[0, 160])
        rescue StandardError => e
          return unless handle_fix_exception(e, { law: @law.id, file: path }, event: "repair_loop:fix_error") == :retry
        end
        nil
      end

      # The diff inside a fence when the reply is fenced, else the reply.
      def diff_of(response)
        response[/^```(?:diff|patch)?[ \t]*\n(.*?)^```/m, 1] || response
      end

      # Each finding's line window, overlapping windows merged, numbered by the
      # file's own line numbers in the heading only so the diff's context stays exact.
      def excerpt_prompt(src, path)
        lines = src.lines
        windows = merged_windows(lines.size)
        ctx = prompt_context_for(violation: {}, path:, style: :diff)
        parts = windows.map do |first, last|
          "Lines #{first}-#{last} of #{lines.size}:\n```#{ctx[:lang]}\n#{lines[(first - 1)..(last - 1)].join}```"
        end
        <<~PROMPT
          #{GOLDEN}
          #{rule_notes}

          File: #{File.basename(path)} (#{ctx[:lang]})
          Findings. Repair each one that is real; leave any you judge a false positive as it is:
          #{finding_lines}

          #{parts.join("\n\n")}

          #{RunLedger.retry_note}

          Reply with ONLY a minimal unified diff for this one file (`--- a/#{File.basename(path)}` / `+++ b/#{File.basename(path)}`, @@ hunks).
          Copy context lines exactly. Change only lines a finding names; do not reformat, reorder or rename anything else.
          If no finding is real, reply exactly: UNCHANGED
        PROMPT
      end

      def merged_windows(total)
        spans = @findings.map { |finding| finding[:line].to_i }.select(&:positive?).sort.map do |line|
          [[line - CONTEXT_LINES, 1].max, [line + CONTEXT_LINES, total].min]
        end
        spans = [[1, [total, 2 * CONTEXT_LINES].min]] if spans.empty?
        spans.each_with_object([]) do |span, merged|
          merged.last && span.first <= merged.last.last + 1 ? merged.last[1] = [merged.last.last, span.last].max : merged << span
        end
      end

      def rule_notes
        @findings.map { |finding| finding[:law].to_s }.uniq
                 .map { |id| "- #{id}: #{@notes[id].to_s.empty? ? "see the finding" : @notes[id]}" }.join("\n")
      end

      def finding_lines
        lines = @findings.sort_by { |finding| finding[:line].to_i }.map do |finding|
          hint = finding[:fix].to_s.strip
          "- line #{finding[:line]}, #{finding[:law]}: #{finding[:message]}#{" (how: #{hint})" unless hint.empty?}"
        end
        lines.join("\n")
      end

      # Learnings are kept per rule, and a file repair spans several.
      def record_outcomes(*) = nil
    end
  end
end
