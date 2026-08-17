# frozen_string_literal: true

# Migrated from data/rules.yml TEMPLATE_LITERALS.
Law.define(:TEMPLATE_LITERALS) do
  source "Airbnb JS Style Guide — template literals (ES6)"
  severity :warn
  languages %i[javascript]
  detect { |line| line.match?(/["']\s*\+\s*\w+\s*\+\s*["']/) }
  fix "Use `Hello ${name}!` template literals."
  bad  "'Hello ' + name + '!'"
  good "`Hello ${name}!`"
end
