# frozen_string_literal: true

# Run using bin/ci — Rails 8.1 local CI (pub4 family apps)

CI.run do
  step "Setup", "bin/setup --skip-server"
  step "Style: Ruby", "bin/rubocop app lib config db/migrate"
  audit = ENV["BUNDLER_AUDIT_UPDATE"] == "1" ? "bin/bundler-audit check --update" : "bin/bundler-audit check"
  step "Security: Gem audit", audit
  step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "bin/rails test"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
end