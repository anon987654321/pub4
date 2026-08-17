# frozen_string_literal: true

# Migrated from data/rules.yml NO_IMPORTANT.
Law.define(:NO_IMPORTANT) do
  source "CSS best practice — avoid !important (MDN)"
  severity :warn
  languages %i[css]
  detect { |line| line.match?(/!\s*important/) }
  fix "Restructure selectors to avoid specificity bankruptcy."
  bad  "color: red !important;"
  good "color: red;"
end
