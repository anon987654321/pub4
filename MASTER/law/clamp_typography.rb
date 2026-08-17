# frozen_string_literal: true

# Migrated from data/rules.yml CLAMP_TYPOGRAPHY.
Law.define(:CLAMP_TYPOGRAPHY) do
  source "CSS fluid typography — clamp() (web.dev)"
  severity :info
  languages %i[css]
  detect { |line| line.match?(/@media.*\{[^}]*font-size:/) }
  fix "Use font-size: clamp(1rem, 2.5vw, 1.5rem)."
  bad  "@media (min-width: 40em) { h1 { font-size: 2rem; } }"
  good "h1 { font-size: clamp(1.5rem, 2.5vw, 2.5rem); }"
end
