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
    app = File.basename(Dir.getwd)
    css_builder = [
      ENV["PUB4_RAILS_ROOT"] && File.join(ENV["PUB4_RAILS_ROOT"], "build_all_css.rb"),
      "/home/dev/pub4/RAILS/build_all_css.rb",
      File.expand_path("../..", __dir__) + "/build_all_css.rb",
      File.expand_path("pub4-rails/RAILS/build_all_css.rb", ENV["HOME"].to_s)
    ].compact.find { |candidate| File.readable?(candidate) }
    if css_builder
      step "Styles: pub4 CSS", "#{RbConfig.ruby} #{css_builder} --app #{app}"
    else
      step "Styles: pub4 CSS", "echo 'build_all_css.rb not found in any known location -- skipping' >&2"
    end
    step("Security: Importmap audit", "bundle exec importmap audit") unless vps_host
    rubocop = 'bundle exec rubocop $(for d in app lib config db/migrate; do [ -d "$d" ] && printf "%s " "$d"; done)'
    step("Style: Ruby", rubocop) unless vps_host
    audit = ENV["BUNDLER_AUDIT_UPDATE"] == "1" ? "bundle exec bundler-audit check --update" : "bundle exec bundler-audit check"
    step "Security: Gem audit", audit
    step "Security: Brakeman", "bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
    step "Tests: DB prepare", "env RAILS_ENV=test bin/rails db:test:prepare"
    step "Tests: Rails", "bin/rails test"
    # System tests spin up a real headless-Chrome session -- too heavy for the
    # 1-vCPU VPS gate (see resource_guard.sh), but must run in local/dev CI.
    # This is also where axe-core accessibility checks live (see
    # test/application_system_test_case.rb's assert_accessible).
    step("Tests: System (a11y)", "bin/rails test:system") unless vps_host
    seed_env = vps_host ? "env RAILS_ENV=test SKIP_BERGEN_DEMO=1" : "env RAILS_ENV=test"
    step "Tests: Seeds", "#{seed_env} bin/rails db:seed:replant"
  end
end