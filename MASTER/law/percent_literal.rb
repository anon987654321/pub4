# frozen_string_literal: true

# Migrated from data/rules.yml PERCENT_LITERAL.
Law.define(:PERCENT_LITERAL) do
  source "Ruby Style Guide — %w/%i array literals"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/\[:[a-z_]+,\s*:[a-z_]+,\s*:[a-z_]+/) }
  fix "Use %i[a b c] for symbol arrays."
  bad  "[:a, :b, :c]"
  good "%i[a b c]"
end
