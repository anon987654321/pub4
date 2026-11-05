# frozen_string_literal: true

# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"
  step "Security: Gem audit", "bundle exec bundler-audit check"
  step "Style: RuboCop", "bundle exec rubocop"
  step "Security: Brakeman", "bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Node tests", "node --test test/*.test.mjs"
  step "Web CI probe", "ruby script/ci_web_probe"
  # Same reason mrdamascy's ci.rb names it: a fresh checkout (or a vm23
  # copy-tree with no development database) must not learn about its missing
  # test schema from a thousand failures inside "Rails tests". Prepare first;
  # the suite then measures behaviour, not database state.
  step "test_db_prepare", "env RAILS_ENV=test bin/rails db:test:prepare"
  step "Rails tests", "bin/rails test"
end
