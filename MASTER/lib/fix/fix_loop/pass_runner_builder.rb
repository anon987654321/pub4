# frozen_string_literal: true

module Master
  module Fix
    class FixLoop
      # Wires PassRunner's own collaborators (committer, scanner, council,
      # visual/opportunity evidence passes) from FixLoop's constructor
      # arguments -- kept separate so NO_GOD_CLASS's line count reflects
      # FixLoop's run/recovery responsibilities on their own.
      module PassRunnerBuilder
        def build_pass_runner(rules:, agent:, scanner:, root:, bus:, learnings:, rollback:,
          ground_truth:, preserve_user_intent:, law_resolver:, homeostat: nil)
          committer = Committer.new(git: @git, bus:, root:,
                                       ground_truth:, preserve_user_intent:)
          conflict_resolver = ConflictResolver.new(root:, bus:, law_resolver:)
          llm_router = LlmRouter.new(agent)
          council = CouncilRound.new(agent:, root:, bus:)
          visual_pass = VisualPass.new(agent:, root:, bus:)
          opportunity_pass = OpportunityPass.new(root:, bus:)
          preamble = self.class.preamble_from_soul

          PassRunner.new(
            bus:, committer:, conflict_resolver:, llm_router:, rollback:, root:,
            rules:, agent:, scanner:, learnings:, preamble:,
            clean_runs_required:,
            plateau_window:,
            ground_truth:, homeostat:, council:, visual_pass:, opportunity_pass:
          )
        end
      end
    end
  end
end
