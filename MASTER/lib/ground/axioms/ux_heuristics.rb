# frozen_string_literal: true

module Master
  module Ground
    module Axioms
      module UxHeuristics
        # Nielsen's 10 Usability Heuristics — applies to CLI, web UI, API errors, and prose.
        HEURISTICS = {.freeze
          h1_visibility: "Visibility of System Status — keep users informed through appropriate feedback within a reasonable time",
          h2_real_world: "Match Between the System and the Real World — speak the user's language, not internal jargon",
          h3_user_control: "User Control and Freedom — provide a clearly marked exit from unwanted states",
          h4_consistency: "Consistency and Standards — follow platform and industry conventions",
          h5_error_prevention: "Error Prevention — prevent problems from occurring rather than relying on error messages",
          h6_recognition: "Recognition Rather than Recall — make elements, actions, and options visible",
          h7_flexibility: "Flexibility and Efficiency of Use — support both novice and expert users",
          h8_minimalism: "Aesthetic and Minimalist Design — every extra unit competes with relevant units",
          h9_error_recovery: "Help Users Recognize, Diagnose, and Recover from Errors — plain language, precise problem, constructive solution",
          h10_help: "Help and Documentation — documentation should help users complete tasks, not explain bad design",
        }.freeze

        SIGNALS = {.freeze
          web: {
            h1_visibility: { checks: %w[loading-indicator turbo:frame-missing offline-fallback],
              failing: "No feedback during navigation or offline state" },
            h3_user_control: { checks: %w[undo back-navigation escape-modal cancel],
              failing: "No exit from modals or destructive actions" },
            h4_consistency: { checks: %w[shared-layout stimulus-conventions semantic-html],
              failing: "Component behavior diverges from shared baseline" },
            h5_error_prevention: { checks: %w[form-label aria-required input-type],
              failing: "Form fields lack <label> or aria-required" },
            h6_recognition: { checks: %w[nav-visible primary-action icon-labels],
              failing: "Primary actions hidden or icon-only without labels" },
            h8_minimalism: { checks: %w[information-density whitespace raw-primaries animation],
              failing: "Visual noise: raw colors, unguarded animations, dense layout" },
            h9_error_recovery: { checks: %w[flash error-format turbo-stream-error],
              failing: "Error messages generic or missing recovery path" },
          },
          cli: {
            h1_visibility: { checks: %w[progress spinner result-line],
              failing: "No output while operation is running — user cannot tell if system is working" },
            h2_real_world: { checks: %w[plain-language no-jargon],
              failing: "Output uses internal symbol names, not human-readable descriptions" },
            h8_minimalism: { checks: %w[no-filler terse single-line],
              failing: "Output contains filler phrases or multi-line where one line suffices" },
            h9_error_recovery: { checks: %w[actionable-error suggestion],
              failing: "Error output does not suggest a corrective action" },
          },
        }.freeze

        def self.cite(heuristic_key, violation, medium: :web)
          h = HEURISTICS.fetch(heuristic_key, heuristic_key.to_s)
          heuristic_number = heuristic_key.to_s[/\d+/]
          "[Nielsen ##{heuristic_number} — #{h.split(' — ').first}] #{violation}"
        end

        def self.number(heuristic_key)
          heuristic_key.to_s[/\d+/].to_i
        end
      end
    end
  end
end
