# frozen_string_literal: true

module Master
  module Design
  module UxHeuristics
    # Nielsen's 10 Usability Heuristics (nngroup.com/articles/ten-usability-heuristics/)
    # Universal principles — applied here to Rails PWA / mobile web surfaces.
    HEURISTICS = {
      h1_visibility:       "Visibility of System Status — keep users informed through appropriate feedback within a reasonable time",
      h2_real_world:       "Match Between the System and the Real World — speak the user's language, not internal jargon",
      h3_user_control:     "User Control and Freedom — provide a clearly marked exit from unwanted states",
      h4_consistency:      "Consistency and Standards — follow platform and industry conventions",
      h5_error_prevention: "Error Prevention — prevent problems from occurring rather than relying on error messages",
      h6_recognition:      "Recognition Rather than Recall — make elements, actions, and options visible",
      h7_flexibility:      "Flexibility and Efficiency of Use — support both novice and expert users",
      h8_minimalism:       "Aesthetic and Minimalist Design — every extra unit competes with relevant units",
      h9_error_recovery:   "Help Users Recognize, Diagnose, and Recover from Errors — plain language, precise problem, constructive solution",
      h10_help:            "Help and Documentation — documentation should help users complete tasks, not explain bad design"
    }.freeze

    # Heuristic → concrete mobile/PWA audit signals
    MOBILE_SIGNALS = {
      h1_visibility: {
        checks:  %w[loading-indicator turbo:frame-missing offline-fallback],
        failing: "No loading feedback during Turbo navigation or offline state — user cannot tell if the system is responding"
      },
      h3_user_control: {
        checks:  %w[undo-action back-navigation escape-modal],
        failing: "No clear exit from modals or destructive actions — missing undo, back, or cancel affordance"
      },
      h4_consistency: {
        checks:  %w[shared-layout stimulus-conventions semantic-html],
        failing: "Inconsistent component behavior across apps — Stimulus controllers or layout landmarks diverge from shared baseline"
      },
      h5_error_prevention: {
        checks:  %w[form-label aria-required input-type],
        failing: "Form fields without <label> or aria-required — users cannot anticipate required input before submission"
      },
      h6_recognition: {
        checks:  %w[nav-visible primary-action-visible icon-labels],
        failing: "Primary actions hidden behind menus or icon-only buttons without visible labels"
      },
      h8_minimalism: {
        checks:  %w[information-density whitespace raw-primaries decorative-animation],
        failing: "Unnecessary visual noise: raw primary colors, unguarded animations, or dense information layout"
      },
      h9_error_recovery: {
        checks:  %w[flash-messages error-format turbo-stream-error],
        failing: "Error messages are generic or missing — no plain-language description or recovery path"
      }
    }.freeze

    # Produce a cited finding string for use in audit output
    def self.cite(heuristic_key, violation)
      h = HEURISTICS.fetch(heuristic_key) { "Unknown heuristic" }
      number = heuristic_key.to_s.match(/h(\d+)/)[1]
      "[Nielsen ##{number} — #{h.split(' — ').first}] #{violation}"
    end
  end
  end
end
