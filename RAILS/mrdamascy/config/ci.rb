# frozen_string_literal: true

# Run using bin/ci. The test database is prepared on its own so a run on a fresh
# checkout (or vm23's copy-tree, where no development database exists) works.
CI.run do
  step "test_db_prepare", "env RAILS_ENV=test bin/rails db:test:prepare"
  step "tests", "env RAILS_ENV=test bin/rails test"
end
