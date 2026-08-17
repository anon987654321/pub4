# frozen_string_literal: true

# Migrated from data/rules.yml MEANINGFUL_NAMES.
Law.define(:MEANINGFUL_NAMES) do
  source "Clean Code — meaningful names (Robert C. Martin)"
  severity :info
  detect { |line| line.match?(/\b(tmp|temp|data|result|val|ret|obj|str|arr|buf)\b\s*=/) }
  fix "Use domain-specific names. user_profile, error_message."
  bad  "tmp = load"
  good "user_profile = load"
end
