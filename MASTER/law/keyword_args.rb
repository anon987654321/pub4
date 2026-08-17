# frozen_string_literal: true

# Migrated from data/rules.yml KEYWORD_ARGS.
Law.define(:KEYWORD_ARGS) do
  source "Ruby Style Guide — keyword args over options hash"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/def \w+\([^)]*,\s*[^:)]+,\s*[^:)]+,\s*[^:)]+\)/) }
  fix "Use keyword arguments for clarity and safety."
  bad  "def build(name, size, color, weight)"
  good "def build(name:, size:, color:, weight:)"
end
