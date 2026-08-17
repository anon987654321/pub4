# frozen_string_literal: true

# Migrated from data/rules.yml PROSE_ACTIVE_VOICE.
Law.define(:PROSE_ACTIVE_VOICE) do
  source "Strunk, Elements of Style (1918) Rule 10 — use the active voice"
  severity :info
  languages %i[prose markdown ruby]
  detect { |line| line.match?(/\b(was|were|is|are|been|be)\s+\w+ed\b/) }
  fix "Recast active: 'the bug was fixed by X' -> 'X fixed the bug'."
  bad  "The bug was fixed by the maintainer."
  good "The maintainer fixed the bug."
end
