# frozen_string_literal: true

# Migrated from data/rules.yml EACH_WITH_OBJECT.
Law.define(:EACH_WITH_OBJECT) do
  source "Ruby Style Guide / RuboCop Style/EachWithObject"
  severity :warn
  languages %i[ruby]
  detect { |line| line.match?(/\.(inject|reduce)\(\s*(\{\s*\}|\[\s*\])\s*\)/) }
  fix "Only when the argument is a literal {} or [] that the block mutates in place. Do NOT rewrite reduce/inject whose block returns the next accumulator (a rebuilt string, a running total, a folded hash) — each_with_object discards that return value and the fold becomes a no-op. If in doubt, leave reduce alone."
  bad  "items.inject({}) { |h, i| h[i] = 1; h }"
  good "items.each_with_object({}) { |i, h| h[i] = 1 }"
end
