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

          def llm_pass(violations:, files:, pass:, deadline: nil)
            rule_violations = violations.group_by { |v| v[:rule].to_s }
            runnable = @rule_order.ordered(violation_counts: @violation_counts)
                                  .select { |rule| rule_violations.key?(rule.id.to_s) }
            fixed = run_dependency_levels(runnable, files:, pass:, rule_violations:, deadline:)
            publish_llm_pass_status(pass:, deadline:)
            fixed
          end

          def run_dependency_levels(runnable, files:, pass:, rule_violations:, deadline:)
            fixed = 0
            @rule_order.dependency_levels(runnable).each do |group|
              break if deadline && Time.now >= deadline
              break if circuit_open?
              results = run_rule_group(group:, files:, pass:, rule_violations:)
              results.each do |rule, result|
                @violation_counts[rule.id] += result[:fixed]
                fixed += result[:fixed]
                @bus&.publish("fix_loop:rule_result", pass:, rule: rule.id, **result)
              end
            end
            fixed
          end

          def publish_llm_pass_status(pass:, deadline:)
            if deadline && Time.now >= deadline
              @bus&.publish("fix_loop:pass_timeout", pass:)
            elsif circuit_open?
              @bus&.publish("fix_loop:llm_skipped", pass:, reason: "circuit_open", open: open_breakers)
            end
          end

          def run_rule_group(group:, files:, pass:, rule_violations:)
            return group.map { |rule| [rule, run_rule_once(rule, files, pass)] } unless disjoint_rule_files?(group, rule_violations)

            group.map { |rule| Thread.new { [rule, run_rule_once(rule, files, pass)] } }.map(&:value)
          end

          def run_rule_once(rule, files, pass)
            rl = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root, bus: @bus, learnings: @learnings)
            rl.injected_preamble = @preamble
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
