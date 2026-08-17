# frozen_string_literal: true

# Migrated from data/rules.yml RATE_LIMITING_MISSING.
Law.define(:RATE_LIMITING_MISSING) do
  source "OWASP API Security — rate limiting"
  severity :error
  languages %i[ruby]
  scope :file
  path "/app/controllers/"
  absent /rate_limit|throttle/
  detect { |text| text.match?(/(login|signup|sign_up|password|reset)/m) }
  fix "Add rate_limit/throttle to sensitive actions."
  bad <<~X
    def login
    end
  X
  good <<~X
    rate_limit to: 5, within: 1.minute
    def login
    end
  X
end
