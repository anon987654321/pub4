# frozen_string_literal: true

# Run using bin/ci — Rails 8.1 local CI (pub4 family apps)
require_relative "../lib/pub4/ci_guard"

ENV["GIT_CEILING_DIRECTORIES"] ||= "/"
ENV["BUNDLER_AUDIT_UPDATE"] ||= "0"
ENV["NPM_CONFIG_CACHE"] ||= File.expand_path("~/.npm")
monorepo_rails = "/home/dev/pub4/DEPLOY/rails"
ENV["PUB4_RAILS_ROOT"] ||= monorepo_rails if File.directory?(File.join(monorepo_rails, "shared"))

vps_host = ENV["PUB4_CI_GUARD"] == "1" || File.exist?("/var/db/pub4_vps") || File.exist?("/etc/relayd.conf")

Pub4::CiGuard.run! do
  CI.run do
    step "Setup", "bin/setup --skip-server"
    step "Styles: Dart Sass", "bin/rails dartsass:build"
    step("Security: Importmap audit", "bin/importmap audit") unless vps_host
    rubocop = 'bin/rubocop $(for d in app lib config db/migrate; do [ -d "$d" ] && printf "%s " "$d"; done)'
    step("Style: Ruby", rubocop) unless vps_host
    audit = ENV["BUNDLER_AUDIT_UPDATE"] == "1" ? "bin/bundler-audit check --update" : "bin/bundler-audit check"
    step "Security: Gem audit", audit
    step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
    step "Tests: Rails", "bin/rails test"
    step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
  end
end