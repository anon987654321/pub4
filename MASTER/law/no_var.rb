# frozen_string_literal: true

# Migrated from data/rules.yml NO_VAR.
Law.define(:NO_VAR) do
  source "Airbnb JS Style Guide — no var (ES6 let/const)"
  severity :error
  languages %i[javascript]
  detect { |line| line.match?(/\bvar\s+\w/) }
  fix "Use const (default) or let (when reassigned)."
  bad  "var x = 1;"
  good "const x = 1;"
end
