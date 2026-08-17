# frozen_string_literal: true

# Migrated from data/rules.yml SAFE_NAVIGATION.
Law.define(:SAFE_NAVIGATION) do
  source "Ruby Style Guide / RuboCop Style/SafeNavigation"
  severity :warn
  languages %i[ruby]
  detect { |line| line.match?(/(\w+)\s*&&\s*\1\.\w+/) }
  fix "Rewrite to x&.foo&.bar"
  bad  "user && user.name"
  good "user&.name"
end
