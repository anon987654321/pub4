# frozen_string_literal: true

# law/prose.rb — every prose law, one Law.define per rule.
# Was 3 one-rule files; Law.load_all and every fixture proof are
# unchanged by the grouping (2026-08-19 file-sprawl consolidation).

# EN_DASH_RANGE lives once, in the registry (cosmetic_rules.rb): it also
# covers yaml and html, skips YAML list items and rule-id lines, and —
# decisive here — `prose` is not a language FILE_LANGUAGE_MAP produces, so
# half this law's declared scope never matched a file (Bringhurst's credit
# rides with the registry version).

# Migrated from data/rules.yml PROSE_ACTIVE_VOICE.
Law.define(:PROSE_ACTIVE_VOICE) do
  source "Strunk, Elements of Style (1918) Rule 10 — use the active voice"
  severity :info
  # `prose` is not a language FILE_LANGUAGE_MAP produces — the note at the
  # top of this file already says so about EN_DASH_RANGE, and these two kept
  # declaring it anyway. markdown and ruby are the real reach.
  languages %i[markdown ruby]
  detect { |line| line.match?(/\b(was|were|is|are|been|be)\s+\w+ed\b/) }
  fix "Recast active: 'the bug was fixed by X' -> 'X fixed the bug'."
  bad  "The bug was fixed by the maintainer."
  good "The maintainer fixed the bug."
end

# Migrated from data/rules.yml PROSE_OMIT_QUALIFIERS.
Law.define(:PROSE_OMIT_QUALIFIERS) do
  source "Strunk, Elements of Style (1918) — the leech words"
  severity :warn
  # `prose` is not a language FILE_LANGUAGE_MAP produces — the note at the
  # top of this file already says so about EN_DASH_RANGE, and these two kept
  # declaring it anyway. markdown and ruby are the real reach.
  languages %i[markdown ruby]
  detect { |line| line.match?(/\b(very|rather|really|quite|pretty|somewhat|just|actually|basically|literally|simply)\b/) }
  fix "Delete the qualifier; let the verb or noun carry the weight."
  bad  "This is very fast."
  good "This is fast."
end
