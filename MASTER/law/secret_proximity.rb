# frozen_string_literal: true

# Migrated from data/rules.yml SECRET_PROXIMITY.
Law.define(:SECRET_PROXIMITY) do
  source "OWASP — no hardcoded secrets/credentials"
  severity :error
  detect { |line| line.match?(/(password|secret|token|api_key|private_key)\s*=\s*['"][^'"]{8,}/) }
  fix "Move secret to environment variable or secrets manager."
  bad  "api_key = 'sk_live_abcdef123456'"
  good "api_key = ENV.fetch('API_KEY')"
end
