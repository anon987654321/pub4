# frozen_string_literal: true

# Migrated from data/rules.yml HASH_FETCH.
Law.define(:HASH_FETCH) do
  source "Ruby Style Guide — Hash#fetch over [] for required keys"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/\w+\[:\w+\]\s*\|\|/) }
  fix "Use hash.fetch(:key, default) for nil-vs-false safety."
  bad  "opts[:size] || 10"
  good "opts.fetch(:size, 10)"
end
