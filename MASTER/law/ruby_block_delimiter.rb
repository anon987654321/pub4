# frozen_string_literal: true

# Migrated from data/rules.yml RUBY_BLOCK_DELIMITER.
Law.define(:RUBY_BLOCK_DELIMITER) do
  source "Ruby Style Guide / RuboCop Style/BlockDelimiters"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/\bdo\b\s*(\|[^|]*\|)?[^\n]*\bend\s*$/) }
  fix "Single-line block on one line -> use { }. Reserve do/end for multi-line."
  bad  "list.each do |x| puts x end"
  good "list.each { |x| puts x }"
end
