# frozen_string_literal: true

# Run using bin/ci. mrdamascy is standalone, so these are its own steps rather
# than RAILS/__shared/config/ci.rb, whose CSS builder, design lints and seed
# replant are written for the pub4-shared apps. The three static checks are the
# same ones those apps run, with the same flags. The test database is prepared on
# its own so a run on a fresh checkout (or vm23's copy-tree, where no
# development database exists) works.

# Refresh the advisory database by default, as the shared CI does: a clean audit
# against whatever ruby-advisory-db shipped inside the installed gem says nothing
# about this tree. Set BUNDLER_AUDIT_UPDATE=0 where there is no network.
ENV["BUNDLER_AUDIT_UPDATE"] ||= "1"
audit = "bundle exec bundler-audit check --config config/bundler-audit.yml"
audit += " --update" if ENV["BUNDLER_AUDIT_UPDATE"] == "1"

# vm23, by the same test the shared CI uses: ci-run.ksh exports
# PUB4_CI_GUARD=1. The box has no browser, so the system tests (headless
# Chrome, axe-core) run in local CI only, as brgen's do.
vps_host = ENV["PUB4_CI_GUARD"] == "1" || File.exist?("/var/db/pub4_vps") || File.exist?("/etc/relayd.conf")

CI.run do
  step "rubocop", "bundle exec rubocop app config db/migrate test"
  step "bundler_audit", audit
  step "brakeman", "bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "test_db_prepare", "env RAILS_ENV=test bin/rails db:test:prepare"
  step "tests", "env RAILS_ENV=test bin/rails test"
  step("system_tests", "env RAILS_ENV=test bin/rails test:system") unless vps_host
end
