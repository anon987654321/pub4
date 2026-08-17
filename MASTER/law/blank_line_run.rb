# frozen_string_literal: true

# One blank line separates two things. Two blank lines separate them by an
# amount nobody agreed on, and the amount is invisible — a reader cannot tell a
# deliberate double gap from a merged patch that left one behind, so the spacing
# stops carrying information the moment it varies.
#
# File-scoped because the defect is a relationship between lines: a single blank
# line is correct, and only its neighbour makes it wrong.
Law.define(:BLANK_LINE_RUN) do
  source "Strunk & White I.1 — vigorous writing is concise, and so is its spacing"
  severity :warn
  languages %i[html]
  scope :file
  # Whitespace-only lines count as blank: a line holding two spaces looks
  # identical to an empty one and is the usual way a run of them survives.
  detect { |text| text.match?(/\n[ \t]*\n[ \t]*\n/) }
  fix "Collapse consecutive blank lines to one."
  bad  "<p>first</p>\n\n\n<p>second</p>\n"
  good "<p>first</p>\n\n<p>second</p>\n"
end
