# frozen_string_literal: true

# Migrated from data/rules.yml TYPOGRAPHY_DISCIPLINE.
Law.define(:TYPOGRAPHY_DISCIPLINE) do
  source "Butterick's Practical Typography (Matthew Butterick)"
  severity :info
  detect { |line| line.match?(/[-=]{3,}|[╭╮╰╯│─]/) }
  fix "No ASCII separators. No box drawing. Whitespace is the layout tool."
  bad  "# ------"
  good "# section"
end
