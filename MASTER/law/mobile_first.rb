# frozen_string_literal: true

# Migrated from data/rules.yml MOBILE_FIRST.
Law.define(:MOBILE_FIRST) do
  source "Mobile First (Luke Wroblewski, 2011)"
  severity :warn
  languages %i[css]
  detect { |line| line.match?(/@media\s*\(\s*max-width/) }
  fix "Use min-width (mobile-first, progressive enhancement)."
  bad  "@media (max-width: 600px) {"
  good "@media (min-width: 600px) {"
end
