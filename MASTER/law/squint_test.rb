# frozen_string_literal: true

# Migrated from data/rules.yml SQUINT_TEST. Folds WHITESPACE_PUNCTUATION (identical detector).
Law.define(:SQUINT_TEST) do
  source "Squint Test readability heuristic (Sandi Metz)"
  severity :info
  scope :file
  detect { |text| text.match?(/\n{4,}/m) }
  fix "One blank line between sections, never more than two consecutive."
  bad <<~X
    a



    b
  X
  good <<~X
    a

    b
  X
end
