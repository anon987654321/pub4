# frozen_string_literal: true

# Migrated from data/rules.yml NO_LONG_TRANSITION.
Law.define(:NO_LONG_TRANSITION) do
  source "style.yml motion budget / FrontendRuleSet MOTION"
  severity :warn
  languages %i[css]
  detect { |line| line.match?(/transition(?:-duration)?\s*:\s*([4-9]\d\d|\d{4,})\s*ms/) }
  fix "Keep transitions ≤300ms."
  bad  "transition-duration: 600ms;"
  good "transition-duration: 200ms;"
end
