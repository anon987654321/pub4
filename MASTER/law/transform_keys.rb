# frozen_string_literal: true

# Migrated from data/rules.yml TRANSFORM_KEYS.
Law.define(:TRANSFORM_KEYS) do
  source "Ruby idiom — Hash#transform_keys/values"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/\.each_with_object\(\{\}\)\s*\{\s*\|\(k,\s*v\),\s*h\|/) }
  fix "Use .transform_values { |v| ... }"
  bad  "h.each_with_object({}) { |(k, v), h| h[k] = v * 2 }"
  good "h.transform_values { |v| v * 2 }"
end
