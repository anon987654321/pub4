# frozen_string_literal: true

# Migrated from data/rules.yml OPTIONAL_CHAINING.
Law.define(:OPTIONAL_CHAINING) do
  source "ECMAScript 2020 — optional chaining (?.)"
  severity :warn
  languages %i[javascript]
  detect { |line| line.match?(/(\w+)\s*&&\s*\1\.\w+/) }
  fix "Rewrite to obj?.foo?.bar"
  bad  "user && user.name"
  good "user?.name"
end
