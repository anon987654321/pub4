# frozen_string_literal: true

# law/prose.rb — every prose law, one Law.define per rule.
# Was 3 one-rule files; Law.load_all and every fixture proof are
# unchanged by the grouping (2026-08-19 file-sprawl consolidation).

# Migrated from data/rules.yml EN_DASH_RANGE.
Law.define(:EN_DASH_RANGE) do
  source "Bringhurst, Elements of Typographic Style — en dash for ranges"
  severity :info
  languages %i[prose markdown]
  detect { |line| line.match?(/\b\d+\s?-\s?\d+\b/) }
  fix "Ranges take an en dash, not a hyphen: 45-75 -> 45–75."
  bad  "The measure should be 45-75 characters."
  good "The measure should be 45–75 characters."
end

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

# Migrated from data/rules.yml PROSE_OMIT_QUALIFIERS.
Law.define(:PROSE_OMIT_QUALIFIERS) do
  source "Strunk, Elements of Style (1918) — the leech words"
  severity :warn
  languages %i[prose markdown ruby]
  detect { |line| line.match?(/\b(very|rather|really|quite|pretty|somewhat|just|actually|basically|literally|simply)\b/) }
  fix "Delete the qualifier; let the verb or noun carry the weight."
  bad  "This is very fast."
  good "This is fast."
end
