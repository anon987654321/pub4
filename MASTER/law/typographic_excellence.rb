# frozen_string_literal: true

# Migrated from data/rules.yml TYPOGRAPHIC_EXCELLENCE.
Law.define(:TYPOGRAPHIC_EXCELLENCE) do
  source "Butterick's Practical Typography (Matthew Butterick)"
  severity :info
  detect { |line| line.match?(/["']\.\.\.["']|["']--["']/) }
  fix "Use ellipsis, em dash, curly quotes in UI strings."
  bad  "label = '...'"
  good "label = '…'"
end
