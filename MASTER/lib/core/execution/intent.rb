# frozen_string_literal: true

module Master::Core::Execution
  # Intent — the distillation of a session's purpose.
  #
  # While Memory holds the chronological trace (history), Intent holds the
  # invariant state: the goal, the chosen approach, and the cumulative
  # evidence. This allows a "display-only resume" where the user sees the
  # history, but the model starts with a clean, focused state.
  class Intent
    attr_accessor :goal, :approach, :evidence_summary, :risk

    def initialize(goal:, approach: nil, evidence_summary: nil, risk: :low)
      @goal = goal
      @approach = approach
      @evidence_summary = evidence_summary
      @risk = risk
    end

    def to_h
      {
        goal: @goal,
        approach: @approach,
        evidence_summary: @evidence_summary,
        risk: @risk,
      }
    end

    def self.from_h(hash)
      new(
        goal: hash[:goal] || hash["goal"],
        approach: hash[:approach] || hash["approach"],
        evidence_summary: hash[:evidence_summary] || hash["evidence_summary"],
        risk: (hash[:risk] || hash["risk"] || :low).to_sym,
      )
    end

    def summarize
      [
        "Goal: #{@goal}",
        (@approach ? "Approach: #{@approach}" : nil),
        (@evidence_summary ? "Verified: #{@evidence_summary}" : nil),
        "Risk: #{@risk}",
      ].compact.join("\n")
    end
  end
end
