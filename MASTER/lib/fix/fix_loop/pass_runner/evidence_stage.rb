# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      class PassRunner
        # Rendered-visual and convergence-opportunity evidence: gathering it,
        # merging it into a pass's findings, and routing it (plus the
        # council-selected improvement stage it runs alongside) to the
        # RuleLoop fix protocol -- separate concern from the deterministic
        # FastStage pipeline and the plain source-violation LlmStage.
        module EvidenceStage
          private

          # Fixes a real bug from the branch this was merged from: it called
          # visual&.value! unconditionally whenever found was non-empty, even
          # when visual was an Err -- and Err#value! raises UnwrapError, not
          # nil. Guarding on visual&.ok?/opportunities&.ok? means an errored
          # pass with other findings already present correctly contributes
          # zero findings instead of raising.
          def merge_evidence_findings(target:, files:, pass:, found:)
            visual = run_visual_pass(target:, files:, pass:)
            found += Array(visual.value!&.fetch(:findings, [])) if visual&.ok?

            opportunities = run_opportunity_pass(target:, files:)
            found += Array(opportunities.value!&.fetch(:findings, [])) if opportunities&.ok?

            [visual, opportunities, found]
          end

          def evidence_abort_result(visual, opportunities)
            @committer.abort_transaction!
            message = [visual, opportunities].select { |result| result&.err? }.map(&:message).join(" / ")
            PassResult.new(status: :plateau, consecutive_clean: 0, message:)
          end

          def run_visual_pass(target:, files:, pass:)
            return unless @visual_pass&.applicable?(target)

            @visual_pass.run(target:, files:, pass:)
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "pass_runner.visual_pass", event_bus: @bus)
            Result.err("rendered visual review: INCONCLUSIVE — #{e.class}: #{e.message}", category: :inconclusive)
          end

          def run_opportunity_pass(target:, files:)
            return unless @opportunity_pass&.applicable?(target)

            @opportunity_pass.run(target:, files:)
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "pass_runner.opportunity_pass", event_bus: @bus)
            Result.err("convergence opportunities: INCONCLUSIVE — #{e.class}: #{e.message}", category: :inconclusive)
          end

          def run_opportunity_stage(findings, files, pass, deadline, council: nil)
            return 0 if Time.now >= deadline || findings.empty?

            loop = RuleLoop.new(
              rule: OpportunityPass::Rule.new(OpportunityPass::RULE_ID),
              agent: @agent, scanner: @scanner, root: @root, bus: @bus,
              learnings: @learnings, committer: @committer,
              visual_custody: @visual_pass&.custody,
            )
            loop.injected_preamble = [@preamble, council_preamble(council)].compact.join("\n\n")
            result = loop.run_once(files, external_violations: findings)
            @bus&.publish("fix_loop:opportunity_fix", pass:, findings: findings.size, fixed: result[:fixed].to_i)
            result[:fixed].to_i
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "pass_runner.opportunity_stage", event_bus: @bus)
            0
          end

          def run_improvement_stage(findings, pass:, files:, deadline:)
            return 0 if findings.empty? || Time.now >= deadline

            rule = CouncilRound::IMPROVEMENT_RULE.new(CouncilRound::IMPROVEMENT_RULE_ID)
            loop = RuleLoop.new(
              rule:, agent: @agent, scanner: @scanner, root: @root, bus: @bus,
              learnings: @learnings, committer: @committer
            )
            loop.injected_preamble = [
              @preamble,
              "Council-selected, anchored micro-improvement. Preserve behavior and make the smallest evidence-backed repair.",
            ].join("\n\n")
            result = loop.run_once(files, external_violations: findings)
            @bus&.publish("fix_loop:improvement_fix", pass:, findings: findings.size, fixed: result[:fixed].to_i)
            result[:fixed].to_i
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "pass_runner.improvement_stage", event_bus: @bus)
            0
          end

          def run_visual_stage(findings, pass:, image:, files:, deadline:)
            return 0 if Time.now >= deadline || findings.empty? || image.nil?

            loop = RuleLoop.new(
              rule: VisualPass::Rule.new(VisualPass::RULE_ID),
              agent: @agent, scanner: @scanner, root: @root, bus: @bus,
              learnings: @learnings, committer: @committer
            )
            loop.injected_preamble = [
              @preamble,
              "The following findings came from the real rendered browser. Use the attached screenshot as evidence. Preserve accessibility, semantics and responsive behavior.",
            ].join("\n\n")
            result = loop.run_once(files, external_violations: findings, image:)
            @bus&.publish("fix_loop:visual_fix", pass:, findings: findings.size, fixed: result[:fixed].to_i)
            result[:fixed].to_i
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "pass_runner.visual_stage", event_bus: @bus)
            0
          end
        end
      end
    end
  end
end
