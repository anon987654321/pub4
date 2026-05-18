# frozen_string_literal: true

module Master
  module Ground
  module Axioms
  module Wcag
    # WCAG 2.x success criteria relevant to web/mobile/CLI output
    # Reference: w3.org/WAI/WCAG21/quickref/
    # Universal: apply to any rendered surface, not just visual UIs.

    Criterion = Data.define(:id, :level, :name, :requirement)

    CRITERIA = [
      Criterion.new(id: "1.4.3",  level: :AA,  name: "Contrast (Minimum)",         requirement: "Text contrast >= 4.5:1 (normal), 3:1 (large text)"),
      Criterion.new(id: "1.4.4",  level: :AA,  name: "Resize Text",                requirement: "Text resizable to 200% without loss of content or function"),
      Criterion.new(id: "1.4.10", level: :AA,  name: "Reflow",                     requirement: "Content reflows at 320px width without horizontal scrolling"),
      Criterion.new(id: "1.4.11", level: :AA,  name: "Non-text Contrast",          requirement: "UI component contrast >= 3:1 against adjacent colors"),
      Criterion.new(id: "1.4.12", level: :AA,  name: "Text Spacing",               requirement: "No loss of content when letter/word/line spacing is increased"),
      Criterion.new(id: "1.4.13", level: :AA,  name: "Content on Hover or Focus",  requirement: "Hover/focus content dismissible, hoverable, persistent"),
      Criterion.new(id: "2.1.1",  level: :A,   name: "Keyboard",                   requirement: "All functionality operable via keyboard"),
      Criterion.new(id: "2.4.7",  level: :AA,  name: "Focus Visible",              requirement: "Keyboard focus indicator is visible"),
      Criterion.new(id: "2.5.3",  level: :A,   name: "Label in Name",              requirement: "Visible label text is part of the accessible name"),
      Criterion.new(id: "2.5.8",  level: :AA,  name: "Target Size (Minimum)",      requirement: "Touch target >= 24x24 CSS px (AA); 44x44 CSS px recommended (AAA)"),
      Criterion.new(id: "3.3.1",  level: :A,   name: "Error Identification",       requirement: "Input errors identified in text and described to the user"),
      Criterion.new(id: "3.3.2",  level: :A,   name: "Labels or Instructions",     requirement: "Labels or instructions provided for user input"),
      Criterion.new(id: "1.3.6",  level: :AAA, name: "Identify Purpose",           requirement: "UI components, icons, regions identified programmatically")
    ].freeze

    # Numeric thresholds extracted for use in audit rules
    TOUCH_TARGET_AA_PX  = 24
    TOUCH_TARGET_AAA_PX = 44
    CONTRAST_NORMAL     = 4.5
    CONTRAST_LARGE      = 3.0
    REFLOW_WIDTH_PX     = 320
    BODY_FONT_MIN_PX    = 16  # baseline for WCAG 1.4.4 reflow + readability
    LINE_HEIGHT_MIN     = 1.5 # WCAG 1.4.12 text spacing baseline

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
