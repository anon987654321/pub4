# frozen_string_literal: true

# Migrated from data/rules.yml MAGIC_COLOR.
Law.define(:MAGIC_COLOR) do
  source "CSS design tokens — no hardcoded color values"
  severity :warn
  languages %i[css scss html javascript]
  detect { |line| line.match?(/#[0-9a-fA-F]{3,6}\b|rgb\(|rgba\(|hsl\(/) }
  fix "Reference a CSS custom property or design token."
  bad  "color: #ff0000;"
  good "color: var(--accent);"
end
