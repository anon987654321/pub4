# frozen_string_literal: true

# Migrated from data/rules.yml RUBY_TERNARY_NOT_NESTED.
Law.define(:RUBY_TERNARY_NOT_NESTED) do
  source "Ruby Style Guide / RuboCop Style/NestedTernaryOperator"
  severity :warn
  languages %i[ruby]
  detect { |line| line.match?(/\?[^?:\n]*\?[^?:\n]*:[^?:\n]*:/) }
  fix "Expand nested ternary to if/elsif/else or a case."
  bad  "a ? b ? c : d : e"
  good "a ? b : c"
end
