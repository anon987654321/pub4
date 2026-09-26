# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      class PassRunner
        # The LLM-driven fix stage: orders runnable rules by dependency level,
        # dispatches each rule group (in parallel when the group's violations
        # touch disjoint files), and tracks circuit/deadline state — separate
        # concern from the deterministic FastStage pipeline.
        module LlmStage
          private

          def llm_pass(violations:, files:, pass:, deadline: nil, council: nil)
            rule_violations = violations.group_by { |v| v[:rule].to_s }
            ordered = @rule_order.ordered(violation_counts: @violation_counts)
            runnable = ordered.select { |rule| rule_violations.key?(rule.id.to_s) }
            if runnable.empty? && rule_violations.any?
              Master::Trace::Dmesg.status(
                "fix0",
                "no registered rule fixes #{rule_violations.keys.first(5).join(", ")}; " \
                "registered: #{ordered.map { |r| r.id.to_s }.first(5).join(", ")}",
              )
            end
            fixed = run_dependency_levels(runnable, files:, pass:, rule_violations:, deadline:, council:)
            publish_llm_pass_status(pass:, deadline:)
            fixed
          end

          def run_dependency_levels(runnable, files:, pass:, rule_violations:, deadline:, council: nil)
            fixed = 0
            breakdown = Hash.new(0)
            @rule_order.dependency_levels(runnable).each do |group|
              break if deadline && Time.now >= deadline
              break if circuit_open?
              results = run_rule_group(group:, files:, pass:, rule_violations:, council:)
              fixed += tally_rule_results(results, breakdown:, pass:)
              @human_decision_required ||= results.any? { |_rule, result| result[:status] == :human_decision }
            end
            report_skip_breakdown(breakdown, pass:)
            fixed
          end

          # A rule that reported no breakdown of its own counts once under its
          # status, so every rule contributes exactly one row either way.
          def tally_rule_results(results, breakdown:, pass:)
            results.sum do |rule, result|
              @violation_counts[rule.id] += result[:fixed].to_i
              tallied = result[:breakdown]
              if tallied.nil? || tallied.empty?
                breakdown[result[:status] || :unknown] += 1
              else
                tallied.each { |outcome, count| breakdown[outcome] += count }
              end
              @bus&.publish("fix_loop:rule_result", pass:, rule: rule.id, **result)
              result[:fixed].to_i
            end
          end

          def report_skip_breakdown(breakdown, pass:)
            return if breakdown.empty?

            parts = breakdown.map { |status, count| "#{count} #{status}" }.join(", ")
            Master::Trace::Dmesg.status("fix0", "pass #{pass}, #{parts}")
            @bus&.publish("fix_loop:skip_breakdown", pass:, **breakdown.transform_keys(&:to_sym))
          end

          def publish_llm_pass_status(pass:, deadline:)
            if deadline && Time.now >= deadline
              @bus&.publish("fix_loop:pass_timeout", pass:)
            elsif circuit_open?
              @bus&.publish("fix_loop:llm_skipped", pass:, reason: "circuit_open", open: open_breakers)
            end
          end

          def run_rule_group(group:, files:, pass:, rule_violations:, council: nil)
            unless disjoint_rule_files?(group, rule_violations)
              return group.map { |rule| [rule, run_rule_once(rule, files, pass, council:)] }
            end

            group.map { |rule| Thread.new { [rule, run_rule_once(rule, files, pass, council:)] } }.map(&:value)
          end

          # What the council picked this pass, as repairs to weigh rather than
          # instructions to copy. The fixer still answers to the rule and to
          # PRESERVE_FIRST: a stronger proposal is not automatically a larger
          # change, and a proposal that breaks the rule it addresses is no repair.
          def council_preamble(council)
            picks = Array(council && council[:cherry_picks]).map { |pick| "- #{pick}" }
            return if picks.empty?

            "COUNCIL\nThe council read these files and argued about them. These are the repairs " \
              "it judged strongest. Prefer the one that satisfies the rule with the smallest " \
              "change that preserves what the code means; ignore any that does neither.\n#{picks.join("\n")}"
          end

          def run_rule_once(rule, files, pass, council: nil)
            rl = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root, bus: @bus,
                              learnings: @learnings, committer: @committer,
                              visual_custody: @visual_pass&.custody)
            rl.injected_preamble = [@preamble, council_preamble(council)].compact.join("\n\n")
            @bus&.publish("fix_loop:tier2_quality_route", pass:, rule: rule.id) if @rule_order.tier2?(rule.id)
            rl.run_once(files)
          end

          def disjoint_rule_files?(rules, rule_violations)
            seen = Set.new
            rules.all? do |rule|
              files = Array(rule_violations[rule.id.to_s]).map { |v| v[:file].to_s }.uniq
              overlap = files.any? { |f| seen.include?(f) }
              files.each { |f| seen << f }
              !overlap
            end
          end
        end
      end
    end
  end
end
