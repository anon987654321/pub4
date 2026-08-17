# frozen_string_literal: true

# Migrated from data/rules.yml GUARD_EXPENSIVE_OPS.
Law.define(:GUARD_EXPENSIVE_OPS) do
  source "MASTER-native (guard expensive operations); Nielsen heuristic 5, error prevention"
  severity :error
  detect { |line| line.match?(/\b(delete_all|destroy_all|drop_table|truncate)\b|rm\s+-rf\b/) }
  fix "Cost estimate before execution. Require opt-in for danger."
  bad  "Session.delete_all"
  good "Session.where(expired: true).find_each(&:destroy)"
end
