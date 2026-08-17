# frozen_string_literal: true

# Migrated from data/rules.yml MEASURE_OPTIMUM.
Law.define(:MEASURE_OPTIMUM) do
  source "Bringhurst, Elements of Typographic Style — the measure (45–75 chars)"
  severity :info
  languages %i[css]
  detect { |line| line.match?(/max-width:\s*([89]\d{2}|\d{4,})px/) }
  fix "Bound running-text columns to ~66ch (≈ 33rem), not wide px values."
  bad  "article { max-width: 960px; }"
  good "article { max-width: 66ch; }"
end
