# frozen_string_literal: true

# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"
  step "Security: Gem audit", "bundle exec bundler-audit check"
  step "Style: RuboCop", "bundle exec rubocop"
  step "Security: Brakeman", "bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Node tests", "node --test test/*.test.mjs"
  step "Web CI probe", "ruby script/ci_web_probe"
  step "Rails tests", "bin/rails test"
end
