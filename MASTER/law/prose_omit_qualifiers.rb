# frozen_string_literal: true

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
