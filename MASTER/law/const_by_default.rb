# frozen_string_literal: true

# Migrated from data/rules.yml CONST_BY_DEFAULT.
Law.define(:CONST_BY_DEFAULT) do
  source "Airbnb JS Style Guide — const over let/var"
  severity :warn
  languages %i[javascript]
  detect { |line| line.match?(/\blet\s+(\w+)\s*=/) }
  fix "Use const unless the variable is reassigned."
  bad  "let total = 0;"
  good "const total = 0;"
end
