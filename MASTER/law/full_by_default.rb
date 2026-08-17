# frozen_string_literal: true

# Migrated from data/rules.yml FULL_BY_DEFAULT.
Law.define(:FULL_BY_DEFAULT) do
  source "MASTER-native (no shallow/lite tiers by default)"
  severity :warn
  detect { |line| line.match?(/\b(shallow|standard|quick|lite|basic|light|simple)\b\s*[|,)\]]\s*\b(deep|full|advanced|complete|thorough)\b/) }
  fix "Drop the degraded tier. If a real cost tradeoff exists, rename to surface the cost (lexical < structural < semantic), not the result quality."
  bad  "modes = [shallow, deep]"
  good "modes = [deep]"
end
