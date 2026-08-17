# frozen_string_literal: true

# Migrated from data/rules.yml IMG_ALT.
Law.define(:IMG_ALT) do
  source "WCAG 1.1.1 Non-text Content (W3C/WAI)"
  severity :error
  languages %i[html]
  detect { |line| line.match?(/<img\s+(?![^>]*alt=)/) }
  fix "Add alt= attribute."
  bad  "<img src=\"a.png\">"
  good "<img src=\"a.png\" alt=\"logo\">"
end
