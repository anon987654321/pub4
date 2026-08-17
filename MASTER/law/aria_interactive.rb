# frozen_string_literal: true

# Migrated from data/rules.yml ARIA_INTERACTIVE.
Law.define(:ARIA_INTERACTIVE) do
  source "WAI-ARIA (W3C) — roles for interactive elements"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(/<(div|span)\s+[^>]*onclick/) }
  fix "Add role= and tabindex= for accessibility."
  bad  "<div onclick=\"go()\">"
  good "<button onclick=\"go()\">"
end
