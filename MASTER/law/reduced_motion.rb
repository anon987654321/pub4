# frozen_string_literal: true

# Migrated from data/rules.yml REDUCED_MOTION.
Law.define(:REDUCED_MOTION) do
  source "WCAG 2.3.3 Animation from Interactions"
  severity :info
  languages %i[css]
  detect { |line| line.match?(/@keyframes|animation\s*:/) }
  fix "Add @media (prefers-reduced-motion: reduce) override."
  bad  "animation: spin 1s infinite;"
  good "@media (prefers-reduced-motion: reduce) { .spin { animation-play-state: paused; } }"
end
