# frozen_string_literal: true

module Master
  module Voice
    class Soul
      # The propose -> diff -> approve/reject workflow for SOUL.md changes —
      # separate from Soul's own read-only accessors and rollback.
      module ProposalLifecycle
        def propose(rationale, agent: @agent)
          return "no agent available for drafting" unless agent

          draft = agent.ask_once(proposal_prompt(rationale)).to_s.strip
          return "draft failed" if draft.empty?

          save_proposal(draft)
        rescue StandardError => e
          "proposal error: #{e.message}"
        end

        def diff
          return "no pending proposal" unless File.exist?(@proposal_path)

          changes = changed_lines(@soul.lines, proposal.lines)
          changes.empty? ? "(no visible changes)" : changes.join("\n")
        end

        def approve
          return "no pending proposal" unless File.exist?(@proposal_path)

          version = bump_version(extract_version, :patch)
          updated = with_version_and_changelog(proposal, version)
          persist(@soul_path, updated)
          File.unlink(@proposal_path)
          @soul = updated
          committed = commit_approval(version)
          "soul updated to v#{version}#{committed ? "" : " (git commit failed)"}"
        rescue StandardError => e
          "approve error: #{e.message}"
        end

        def reject
          return "no pending proposal" unless File.exist?(@proposal_path)

          File.unlink(@proposal_path)
          "proposal rejected"
        end

        def propose_from_violations(rule_id, sample_violations, agent: @agent)
          return "no agent available" unless agent

          examples = sample_violations.first(3).map { |violation| violation_example(violation) }.join("\n")
          rationale = "Recurring scan rule '#{rule_id}' flagged #{sample_violations.size} violations " \
                      "across multiple files and cycles:\n#{examples}\nPropose whether the codebase axioms or soul " \
                      "principles should acknowledge this pattern or whether the rule needs refinement."
          propose(rationale, agent:)
        end
      end
    end
  end
end
