# frozen_string_literal: true

# Migrated from data/rules.yml IMMUTABLE.
Law.define(:IMMUTABLE) do
  source "Effective Java — minimize mutability (Joshua Bloch); FP"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/^\s*[A-Z][A-Z_]*\s*=\s*(?:\[[^\]\n]*\]|\{[^}\n]*\})\s*$/) }
  fix "Freeze collections. Use frozen/const by default."
  bad  "COLORS = [:red, :blue]"
  good "COLORS = [:red, :blue].freeze"
end
