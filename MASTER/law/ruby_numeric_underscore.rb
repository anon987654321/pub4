# frozen_string_literal: true

# Migrated from data/rules.yml RUBY_NUMERIC_UNDERSCORE.
Law.define(:RUBY_NUMERIC_UNDERSCORE) do
  source "Ruby Style Guide / RuboCop Style/NumericLiterals"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/[^\d_.]\d{5,}(?![\d_])/) }
  fix "Group digits in threes: 1000000 -> 1_000_000."
  bad  "max = 1000000"
  good "max = 1_000_000"
end
