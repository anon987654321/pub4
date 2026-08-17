# frozen_string_literal: true

# Migrated from data/rules.yml BUTTON_OVER_ANCHOR.
Law.define(:BUTTON_OVER_ANCHOR) do
  source "WAI-ARIA Authoring Practices — button vs link (W3C)"
  severity :warn
  languages %i[html]
  detect { |line| line.match?(/<a\s+href=["']#["']/) }
  fix "Use <button>. Accessible by default."
  bad  "<a href=\"#\">Open</a>"
  good "<button type=\"button\">Open</button>"
end
