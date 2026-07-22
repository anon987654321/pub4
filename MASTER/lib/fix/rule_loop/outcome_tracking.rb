# frozen_string_literal: true

module Master
  module Fix
    class RuleLoop
      # Aggregates one batch's per-violation fix_violation results into a
      # pass-level outcome and records it to @learnings -- separate concern
      # from actually attempting a fix (fix_strategies.rb) or verifying one
      # (fix_verification.rb).
      module OutcomeTracking
        private

        # Only a genuine, attempted-and-failed fix should count as :stuck for
        # fix_quality's purposes -- a violation skipped by policy (confidence
        # gate, stale fingerprint) was never actually attempted, and counting
        # it the same as a real defect silently poisons that rule's quality
        # score, which then deprioritizes it further next round: exactly the
        # "banned a working tool over recoverable failures" trap OpenCrabs
        # documented (feedback_policy.rs, issue #236) after making the same
        # mistake. :skipped is still recorded (queryable) but excluded from
        # fix_quality's denominator entirely.
        def fix_batch(violations)
          results = violations.uniq { |violation| violation[:file] }.map { |violation| fix_violation(violation) }
          @all_skipped = results.any? && results.all? { |r| r.is_a?(Symbol) && r.to_s.start_with?("skip_") }
          log_skip_breakdown(results)
          results.count { |r| r == true }
        end

        # A single aggregate line per rule/pass, not one per violation --
        # thousands of violations would otherwise flood the dmesg stream the
        # way per-file rubocop output already did earlier this session.
        def log_skip_breakdown(results)
          tally = results.tally
          confidence = tally[:skip_confidence].to_i
          fingerprint = tally[:skip_fingerprint].to_i
          return if (confidence + fingerprint).zero?

          Master::Trace::Dmesg.status(
            "fix0",
            "skip_breakdown rule=#{@rule.id} confidence=#{confidence} fingerprint=#{fingerprint} total=#{results.size}",
          )
        end

        def pass_outcome(fixed)
          return :fixed if fixed.positive?
          return :skipped if @all_skipped

          :stuck
        end

        def record_outcomes(files, outcome)
          return unless @learnings

          extensions = files.filter_map do |file|
            ext = File.extname(file).downcase.delete(".")
            ext unless ext.empty?
          end
          ext = extensions.tally.max_by { |_, count| count }&.first || "unknown"
          @learnings.record(rule: @rule.id, file_type: ext, outcome:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "rule_loop.record_outcomes", event_bus: @bus, rule: @rule.id)
        end
      end
    end
  end
end
