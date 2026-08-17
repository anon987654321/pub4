# frozen_string_literal: true

# Migrated from data/rules.yml LOGICAL_PROPERTIES.
Law.define(:LOGICAL_PROPERTIES) do
  source "CSS Logical Properties and Values (W3C)"
  severity :info
  languages %i[css]
  detect { |line| line.match?(/(margin|padding)-(left|right):/) }
  fix "Use margin-inline-start/end, padding-inline-start/end."
  bad  "margin-left: 8px;"
  good "margin-inline-start: 8px;"
end
