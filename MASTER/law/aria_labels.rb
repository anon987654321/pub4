# frozen_string_literal: true

# Migrated from data/rules.yml ARIA_LABELS.
Law.define(:ARIA_LABELS) do
  source "WCAG 4.1.2 Name, Role, Value (W3C/WAI)"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(/<(button|input|select|textarea)\s+(?![^>]*(?:aria-label|aria-labelledby|id=))/) }
  fix "Add aria-label, aria-labelledby, or id paired with <label for>."
  bad  "<button type=\"button\">"
  good "<button type=\"button\" aria-label=\"close\">"
end
