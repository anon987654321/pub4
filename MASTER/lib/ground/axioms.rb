# frozen_string_literal: true

module Master
  module Ground
    module Axioms
      module RailsDoctrine
        # Nine pillars from rubyonrails.org/doctrine (DHH); cite when justifying architectural decisions.
        PILLARS = {
          happiness: "Optimize for programmer happiness",
          convention: "Convention over Configuration",
          omakase: "The menu is omakase",
          no_one_paradigm: "No one paradigm",
          beautiful_code: "Exalt beautiful code",
          sharp_knives: "Provide sharp knives",
          integrated: "Value integrated systems",
          progress: "Progress over stability",
          big_tent: "Push up a big tent",
        }.freeze

        # Database-backed adapters; eliminates Redis/PaaS dependency. Doctrine: :integrated.
        SOLID_TRIFECTA = %w[solid_queue solid_cache solid_cable].freeze

        def self.cite(pillar, rationale)
          name = PILLARS.fetch(pillar) { pillar.to_s }
          "[Rails Doctrine — #{name}] #{rationale}"
        end
      end

      module UxHeuristics
        # Nielsen's 10 Usability Heuristics — applies to CLI, web UI, API errors, and prose.
        HEURISTICS = {
          h1_visibility: "Visibility of System Status — keep users informed through appropriate feedback within a reasonable time",
          h2_real_world: "Match Between the System and the Real World — speak the user's language, not internal jargon",
          h3_user_control: "User Control and Freedom — provide a clearly marked exit from unwanted states",
          h4_consistency: "Consistency and Standards — follow platform and industry conventions",
          h5_error_prevention: "Error Prevention — prevent problems from occurring instead of relying on error messages",
          h6_recognition: "Recognition Rather than Recall — make elements, actions, and options visible",
          h7_flexibility: "Flexibility and Efficiency of Use — support both novice and expert users",
          h8_minimalism: "Aesthetic and Minimalist Design — every extra unit competes with relevant units",
          h9_error_recovery: "Help Users Recognize, Diagnose, and Recover from Errors — plain language, precise problem, constructive solution",
          h10_help: "Help and Documentation — documentation should help users complete tasks, not explain bad design",
        }.freeze

        SIGNALS = {
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

      module Wcag
        # WCAG 2.x success criteria — applies to web, mobile, CLI, any rendered surface.
        Criterion = Data.define(:id, :level, :name, :requirement)

        CRITERIA = [
          Criterion.new(id: "1.4.3", level: :AA, name: "Contrast (Minimum)",
            requirement: "Text contrast >= 4.5:1 (normal), 3:1 (large text)"),
          Criterion.new(id: "1.4.4", level: :AA, name: "Resize Text",
            requirement: "Text resizable to 200% without loss of content or function"),
          Criterion.new(id: "1.4.10", level: :AA, name: "Reflow",
            requirement: "Content reflows at 320px width without horizontal scrolling"),
          Criterion.new(id: "1.4.11", level: :AA, name: "Non-text Contrast",
            requirement: "UI component contrast >= 3:1 against adjacent colors"),
          Criterion.new(id: "1.4.12", level: :AA, name: "Text Spacing",
            requirement: "No loss of content when users increase letter/word/line spacing"),
          Criterion.new(id: "1.4.13", level: :AA, name: "Content on Hover or Focus",
            requirement: "Hover/focus content dismissible, hoverable, persistent"),
          Criterion.new(id: "2.1.1", level: :A, name: "Keyboard",
            requirement: "All functionality operable via keyboard"),
          Criterion.new(id: "2.4.7", level: :AA, name: "Focus Visible",
            requirement: "Keyboard focus indicator is visible"),
          Criterion.new(id: "2.5.3", level: :A, name: "Label in Name",
            requirement: "Visible label text is part of the accessible name"),
          Criterion.new(id: "2.5.8", level: :AA, name: "Target Size (Minimum)",
            requirement: "Touch target >= 24x24 CSS px (AA); 44x44 CSS px recommended (AAA)"),
          Criterion.new(id: "3.3.1", level: :A, name: "Error Identification",
            requirement: "Input errors identified in text and described to the user"),
          Criterion.new(id: "3.3.2", level: :A, name: "Labels or Instructions",
            requirement: "Labels or instructions provided for user input"),
          Criterion.new(id: "1.3.6", level: :AAA, name: "Identify Purpose",
            requirement: "UI components, icons, regions identified programmatically"),
        ].freeze

        TOUCH_TARGET_AA_PX = 24
        TOUCH_TARGET_AAA_PX = 44
        CONTRAST_NORMAL = 4.5
        CONTRAST_LARGE = 3.0
        REFLOW_WIDTH_PX = 320
        BODY_FONT_MIN_PX = 16
        LINE_HEIGHT_MIN = 1.5

        def self.cite(criterion_id, violation)
          c = CRITERIA.find { |cr| cr.id == criterion_id }
          label = c ? "WCAG #{c.id} #{c.level} — #{c.name}" : "WCAG #{criterion_id}"
          "[#{label}] #{violation}"
        end

        def self.find(criterion_id)
          CRITERIA.find { |c| c.id == criterion_id }
        end
      end
    end
  end
end
