# frozen_string_literal: true

# Migrated from data/rules.yml FOR_OF.
Law.define(:FOR_OF) do
  source "Airbnb JS Style Guide — for...of over for...in"
  severity :error
  languages %i[javascript]
  detect { |line| line.match?(/for\s*\(\s*(const|let|var)\s+\w+\s+in\s+/) }
  fix "for...in iterates prototype properties. Use for...of."
  bad  "for (const k in list) {"
  good "for (const k of list) {"
end
