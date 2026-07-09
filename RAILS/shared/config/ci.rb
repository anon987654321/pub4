# frozen_string_literal: true

# Run using bin/ci — Rails 8.1 local CI (pub4 family apps)
require "rbconfig"
require_relative "../lib/pub4/ci_guard"

ENV["GIT_CEILING_DIRECTORIES"] ||= "/"
ENV["BUNDLER_AUDIT_UPDATE"] ||= "0"
ENV["NPM_CONFIG_CACHE"] ||= File.expand_path("~/.npm")
monorepo_rails = "/home/dev/pub4/RAILS"
ENV["PUB4_RAILS_ROOT"] ||= monorepo_rails if File.directory?(File.join(monorepo_rails, "shared"))

vps_host = ENV["PUB4_CI_GUARD"] == "1" || File.exist?("/var/db/pub4_vps") || File.exist?("/etc/relayd.conf")

Pub4::CiGuard.run! do
  CI.run do
    step "Setup", "bin/setup --skip-server"
    rails_root = ENV["PUB4_RAILS_ROOT"] || File.expand_path("../..", __dir__)
    app = File.basename(Dir.getwd)
    css_builder = File.join(rails_root, "build_all_css.rb")
    unless File.readable?(css_builder)
      fallback = File.expand_path("pub4-rails/RAILS/build_all_css.rb", ENV["HOME"].to_s)
      css_builder = fallback if File.readable?(fallback)
    end
    step "Styles: pub4 CSS", "#{RbConfig.ruby} #{css_builder} --app #{app}"
    step("Security: Importmap audit", "bundle exec importmap audit") unless vps_host
    rubocop = 'bundle exec rubocop $(for d in app lib config db/migrate; do [ -d "$d" ] && printf "%s " "$d"; done)'
    step("Style: Ruby", rubocop) unless vps_host
    audit = ENV["BUNDLER_AUDIT_UPDATE"] == "1" ? "bundle exec bundler-audit check --update" : "bundle exec bundler-audit check"
    step "Security: Gem audit", audit
    step "Security: Brakeman", "bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
    step "Tests: DB prepare", "env RAILS_ENV=test bin/rails db:prepare"
    step "Tests: Rails", "bin/rails test"
    step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
  end
end