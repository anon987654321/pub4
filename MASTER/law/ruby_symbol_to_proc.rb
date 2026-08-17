# frozen_string_literal: true

# Migrated from data/rules.yml RUBY_SYMBOL_TO_PROC.
Law.define(:RUBY_SYMBOL_TO_PROC) do
  source "Ruby Style Guide / RuboCop Style/SymbolProc"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/\{\s*\|(\w+)\|\s*\1\.[a-z_]+\s*\}/) }
  fix "Collapse { |x| x.name } -> (&:name)."
  bad  "names = users.map { |u| u.name }"
  good "names = users.map(&:name)"
end
