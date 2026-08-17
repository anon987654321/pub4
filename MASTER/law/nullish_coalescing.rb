# frozen_string_literal: true

# Migrated from data/rules.yml NULLISH_COALESCING.
Law.define(:NULLISH_COALESCING) do
  source "ECMAScript 2020 — nullish coalescing (??)"
  severity :info
  languages %i[javascript]
  detect { |line| line.match?(/(\w+)\s*\|\|\s*\w+/) }
  fix "Use ?? when 0 or '' are valid values."
  bad  "count || fallback"
  good "count ?? fallback"
end
