# frozen_string_literal: true

module Master
  module Loop
  class AutoLoop
    module FixEvaluator
      ERROR_TRUNCATE = 200
      private

      def build_fix_prompt(violation, src)
        "#{constitutional_preamble}\n\n" \
          "Fix this Ruby violation in #{violation[:file]}.\n" \
          "Rule: #{violation[:rule]}\n" \
          "Issue: #{violation[:message]} (line #{violation[:line]})\n\n" \
          "Return ONLY the corrected Ruby file content, no explanation.\n\n" \
          "```ruby\n#{src}\n```"
      end

      def axioms=(text)
        @injected_axioms = text
      end

      def constitutional_preamble
        @constitutional_preamble ||= @injected_axioms || begin
          soul  = Master.load_yaml(File.join(Master::ROOT, "data", "soul.yml"))
          rules = Master.load_yaml(File.join(Master::ROOT, "data", "rules.yml"))
          abs    = soul.fetch("absolute", {})
          golden = abs["golden_rule"] || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
          zen    = rules.fetch("zen", {})
          lines  = ["Constitutional constraints:", "- Golden rule: #{golden}"]
          zen.each_value { |v| lines << "- #{v}" } if zen.is_a?(Hash)
          abs.fetch("code_rules", {}).each { |k, v| lines << "- #{k}: #{v}" }
          abs.fetch("aesthetic_rules", {}).each { |k, v| lines << "- #{k}: #{v}" }
          lines.join("\n")
        rescue StandardError => _e
          "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        end
      end

      def reflected_prompt(base, last_error, attempt)
        # Bounded by MAX_FIX_RETRIES in the calling Reflexion.run loop.
        "Prior attempt (#{attempt}) failed with: #{last_error[0, ERROR_TRUNCATE]}\n" \
          "Reflect briefly on what went wrong, then revise.\n\n" \
          "#{base}"
      end

      def extract_code(text)
        return text.match(/```ruby\n(.*?)```/m)[1].strip if text.match?(/```ruby\n(.*?)```/m)
        return text.match(/```\n(.*?)```/m)[1].strip if text.match?(/```\n(.*?)```/m)
        return text.strip if text.match?(/frozen_string_literal|module |class /)
        nil
      end

      def confidence_score(code, original_src)
        return 0.0 if code.nil? || code.strip.empty?
        score = 0.0
        score += SCORE_INCREMENT if code.include?("# frozen_string_literal: true")
        score += SCORE_INCREMENT if code.match?(/\A.*?(?:module |class )[A-Z]/m)
        ratio  = code.bytesize.to_f / [original_src.bytesize, 1].max
        score += SCORE_INCREMENT if ratio >= MIN_SIZE_RATIO && ratio <= MAX_SIZE_RATIO
        score += SCORE_INCREMENT if syntax_ok?(code)
        score
      end

      def syntax_ok?(content)
        require "tempfile"
        Tempfile.open(["al_chk", ".rb"]) do |f|
          f.binmode
          f.write(content.encode("UTF-8", invalid: :replace, undef: :replace))
          f.flush
          system("ruby", "-c", f.path, out: File::NULL, err: File::NULL)
        end
      rescue StandardError => _e
        false
      end

      def track_recurrence(violations)
        return unless @soul
        tally = violations.group_by { |v| v[:rule].to_s }.transform_values(&:size)
        tally.each do |rule_id, count|
          @rule_recurrence[rule_id] += 1
          next unless @rule_recurrence[rule_id] >= 3
          @rule_recurrence.delete(rule_id)
          sample = violations.select { |v| v[:rule].to_s == rule_id }.first(5)
          @bus&.publish("autoloop:soul_proposal", rule: rule_id, sample: sample)
          @bus&.publish("autoloop:soul_proposal", rule: rule_id, result: "queued")
        end
        (@rule_recurrence.keys - tally.keys).each { |k| @rule_recurrence.delete(k) }
      end
    end
  end
  end
end
