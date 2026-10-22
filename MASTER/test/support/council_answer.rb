# frozen_string_literal: true

require "json"

# A critic answer in the shape InterModelContract accepts. A stub agent that answers in prose
# is refused, retried at temperature 0 and refused again, so its persona never answers.
# The default is the contract's own "nothing to act on"; a critical finding from a veto role vetoes.
module CouncilAnswer
  EVIDENCE = { "location" => "snippet:1", "evidence" => "The supplied snippet." }.freeze

  def self.json(severity: "info", claim: "no actionable issue under charge")
    finding = EVIDENCE.merge("severity" => severity, "claim" => claim, "proposed_repair" => "none")
    {
      "position" => "independent", "position_reason" => "Reviewed the supplied snippet alone.",
      "position_evidence" => [EVIDENCE], "findings" => [finding]
    }.to_json
  end
end
