# frozen_string_literal: true

# Migrated from data/rules.yml EN_DASH_RANGE.
Law.define(:EN_DASH_RANGE) do
  source "Bringhurst, Elements of Typographic Style — en dash for ranges"
  severity :info
  languages %i[prose markdown]
  detect { |line| line.match?(/\b\d+\s?-\s?\d+\b/) }
  fix "Ranges take an en dash, not a hyphen: 45-75 -> 45–75."
  bad  "The measure should be 45-75 characters."
  good "The measure should be 45–75 characters."
end
